package main

// openrgb.go: the OpenRGB SDK client. One concern: speaking OpenRGB's binary
// protocol over its local TCP socket (127.0.0.1:6742), so the rest of the
// lighting code works in Go structs instead of bytes.
//
// The SDK is used rather than the `openrgb` CLI because only the SDK can read a
// device back: which modes it advertises, which knobs each mode actually has,
// what it is set to right now, and whether it can store a mode in its own
// memory. The CLI can only fire and forget at every device at once, which is
// exactly the behaviour that gets OpenRGB blamed for reconfiguring keyboards.

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"time"
)

const (
	orgbAddr     = "127.0.0.1:6742"
	orgbProtocol = 6
	orgbClient   = "ryoku-hub"
)

// packet ids (NetworkProtocol.h). Only the ones Ryoku needs.
const (
	pktControllerCount   = 0
	pktAck               = 10
	pktControllerData    = 1
	pktProtocolVersion   = 40
	pktClientName        = 50
	pktDeviceListUpdated = 100
	pktUpdateLEDs        = 1050
	pktUpdateZoneLEDs    = 1051
	pktUpdateMode        = 1101
	pktSaveMode          = 1102
)

// mode capability bits (RGBController.h MODE_FLAG_*).
const (
	modeHasSpeed       = 1 << 0
	modeHasDirLR       = 1 << 1
	modeHasDirUD       = 1 << 2
	modeHasDirHV       = 1 << 3
	modeHasBrightness  = 1 << 4
	modeHasPerLEDColor = 1 << 5
	modeHasModeColor   = 1 << 6
	modeManualSave     = 1 << 8
	modeAutomaticSave  = 1 << 9
)

// direction values (RGBController.h MODE_DIRECTION_*), by the name Ryoku stores.
var orgbDirections = []struct {
	Name string
	Flag uint32
	Val  uint32
}{
	{"Left", modeHasDirLR, 0},
	{"Right", modeHasDirLR, 1},
	{"Up", modeHasDirUD, 2},
	{"Down", modeHasDirUD, 3},
	{"Horizontal", modeHasDirHV, 4},
	{"Vertical", modeHasDirHV, 5},
}

// device types (RGBController.h device_type), indexed by the wire value.
var orgbTypes = []string{
	"Motherboard", "DRAM", "GPU", "Cooler", "LED Strip", "Keyboard", "Mouse",
	"Mousemat", "Headset", "Headset Stand", "Gamepad", "Light", "Speaker",
	"Virtual", "Storage", "Case", "Microphone", "Accessory", "Keypad",
	"Laptop", "Monitor", "Unknown",
}

func orgbTypeName(v int32) string {
	if v >= 0 && int(v) < len(orgbTypes) {
		return orgbTypes[v]
	}
	return "Unknown"
}

// orgbMode = one lighting mode as the device describes it. The raw wire fields
// are kept so a write can echo them back untouched; only the knobs the user
// actually turned are changed.
type orgbMode struct {
	Name      string
	Value     int32
	Flags     uint32
	SpeedMin  uint32
	SpeedMax  uint32
	BriMin    uint32
	BriMax    uint32
	ColorsMin uint32
	ColorsMax uint32
	Speed     uint32
	Bri       uint32
	Direction uint32
	ColorMode uint32
	Colors    []uint32
}

func (m orgbMode) has(flag uint32) bool { return m.Flags&flag != 0 }

// CanSave: the device can store this mode in its own memory, so the look
// survives OpenRGB quitting. Automatic-save devices do it without being asked.
func (m orgbMode) CanSave() bool { return m.has(modeManualSave) }

// Directions the mode advertises, by name.
func (m orgbMode) Directions() []string {
	var out []string
	for _, d := range orgbDirections {
		if m.has(d.Flag) {
			out = append(out, d.Name)
		}
	}
	return out
}

type orgbZone struct {
	Name  string
	Type  int32
	LEDs  uint32
	Start uint32 // first LED index of this zone in the device LED list
	// the physical grid, when the device reports one: Map[row*W+col] is an LED
	// index (or 0xFFFFFFFF for a gap). It is what lets an effect travel across a
	// keyboard instead of along an arbitrary index order.
	W, H uint32
	Map  []uint32
}

// orgbDevice = one controller: its identity, its zones, and every mode it
// advertises. Index is its place in the current list; Address is the value the
// negotiated protocol uses for requests on this connection.
type orgbDevice struct {
	Provider     string
	ProviderPath string
	Aliases      []string
	Index        int
	Address      uint32
	Type         string
	Name         string
	Vendor       string
	Description  string
	Version      string
	Serial       string
	Location     string
	ActiveMode   int
	Modes        []orgbMode
	Zones        []orgbZone
	LEDCount     int
}

// mode looks a mode up by name.
func (d orgbDevice) mode(name string) (int, orgbMode, bool) {
	for i, m := range d.Modes {
		if m.Name == name {
			return i, m, true
		}
	}
	return 0, orgbMode{}, false
}

// orgbConn = a live SDK connection.
type orgbConn struct {
	c       net.Conn
	dur     time.Duration
	version uint32
	// set when the server announced a changed device list, which is how it says
	// "detection has finished" after a cold start.
	listChanged bool
}

// orgbDial connects and completes the handshake: advertise the protocol Ryoku
// speaks, then name the client so the OpenRGB GUI shows who is talking.
func orgbDial(timeout time.Duration) (*orgbConn, error) {
	c, err := net.DialTimeout("tcp", orgbAddr, timeout)
	if err != nil {
		return nil, err
	}
	o := &orgbConn{c: c, dur: timeout}
	serverVersion, err := o.negotiate()
	if err != nil {
		c.Close()
		return nil, err
	}
	o.version = min(serverVersion, uint32(orgbProtocol))
	if o.version < 5 {
		c.Close()
		return nil, fmt.Errorf("openrgb protocol %d is too old; Ryoku requires protocol 5 or newer", o.version)
	}
	if err := o.write(0, pktClientName, append([]byte(orgbClient), 0)); err != nil {
		c.Close()
		return nil, err
	}
	return o, nil
}

func (o *orgbConn) Close() error { return o.c.Close() }

// negotiate advertises Ryoku's protocol. The server records the lower supported
// version while its reply reports the server's own highest version.
func (o *orgbConn) negotiate() (uint32, error) {
	if err := o.send(0, pktProtocolVersion, u32(orgbProtocol)); err != nil {
		return 0, err
	}
	body, err := o.reply(pktProtocolVersion)
	if err != nil {
		return 0, err
	}
	if len(body) < 4 {
		return 0, errors.New("openrgb: bad protocol reply")
	}
	return binary.LittleEndian.Uint32(body), nil
}

// reply waits for the answer to the request just sent, stepping over anything
// the server pushes in the meantime. OpenRGB announces a changed device list
// unasked, and protocol 6 acknowledges earlier packets after their replies.
func (o *orgbConn) reply(want uint32) ([]byte, error) {
	for {
		_, id, body, err := o.recv()
		if err != nil {
			return nil, err
		}
		if id == want {
			return body, nil
		}
		o.observe(id)
	}
}

func (o *orgbConn) write(dev, id uint32, body []byte) error {
	if err := o.send(dev, id, body); err != nil || o.version < 6 {
		return err
	}
	return o.waitAck(dev, id)
}

func (o *orgbConn) waitAck(dev, want uint32) error {
	for {
		gotDev, id, body, err := o.recv()
		if err != nil {
			return err
		}
		if id != pktAck {
			o.observe(id)
			continue
		}
		if len(body) < 8 {
			return errors.New("openrgb: bad acknowledgement")
		}
		acked, status := binary.LittleEndian.Uint32(body), binary.LittleEndian.Uint32(body[4:])
		if gotDev != dev || acked != want {
			continue
		}
		if status != 0 {
			return fmt.Errorf("openrgb: packet %d failed with status %d", want, status)
		}
		return nil
	}
}

func (o *orgbConn) observe(id uint32) {
	if id == pktDeviceListUpdated {
		o.listChanged = true
	}
}

func (o *orgbConn) send(dev, id uint32, body []byte) error {
	if err := o.c.SetWriteDeadline(time.Now().Add(o.dur)); err != nil {
		return err
	}
	head := make([]byte, 16, 16+len(body))
	copy(head, "ORGB")
	binary.LittleEndian.PutUint32(head[4:], dev)
	binary.LittleEndian.PutUint32(head[8:], id)
	binary.LittleEndian.PutUint32(head[12:], uint32(len(body)))
	_, err := o.c.Write(append(head, body...))
	return err
}

func (o *orgbConn) recv() (dev, id uint32, body []byte, err error) {
	if err = o.c.SetReadDeadline(time.Now().Add(o.dur)); err != nil {
		return
	}
	head := make([]byte, 16)
	if _, err = io.ReadFull(o.c, head); err != nil {
		return
	}
	if string(head[:4]) != "ORGB" {
		err = errors.New("openrgb: bad packet magic")
		return
	}
	dev = binary.LittleEndian.Uint32(head[4:])
	id = binary.LittleEndian.Uint32(head[8:])
	size := binary.LittleEndian.Uint32(head[12:])
	if size > 8<<20 {
		err = fmt.Errorf("openrgb: packet too large (%d bytes)", size)
		return
	}
	body = make([]byte, size)
	_, err = io.ReadFull(o.c, body)
	return
}

// Devices enumerates every controller the server has detected.
func (o *orgbConn) Devices() ([]orgbDevice, error) {
	if err := o.send(0, pktControllerCount, nil); err != nil {
		return nil, err
	}
	body, err := o.reply(pktControllerCount)
	if err != nil {
		return nil, err
	}
	if len(body) < 4 {
		return nil, errors.New("openrgb: bad controller count reply")
	}
	n := int(binary.LittleEndian.Uint32(body))
	if o.version >= 6 && len(body) != 4+4*n {
		return nil, errors.New("openrgb: bad controller id list")
	}
	out := make([]orgbDevice, 0, n)
	for i := range n {
		address := uint32(i)
		request := u32(o.version)
		if o.version >= 6 {
			address = binary.LittleEndian.Uint32(body[4+4*i:])
			request = nil
		}
		if err := o.send(address, pktControllerData, request); err != nil {
			return nil, err
		}
		data, err := o.reply(pktControllerData)
		if err != nil {
			return nil, err
		}
		d, err := parseDevice(data, o.version)
		if err != nil {
			return nil, fmt.Errorf("device %d: %w", i, err)
		}
		d.Index = i
		d.Address = address
		out = append(out, d)
	}
	return out, nil
}

// SetMode switches the device to mode idx, carrying the knobs the caller
// changed. Everything else is echoed back exactly as the device reported it.
func (o *orgbConn) SetMode(dev orgbDevice, idx int, m orgbMode) error {
	return o.write(dev.Address, pktUpdateMode, modePayload(o.version, idx, m))
}

// SaveMode writes the mode into the device's own memory, so the look survives
// OpenRGB (and the machine) shutting down. Only ever called on explicit request:
// on a device with onboard profiles this overwrites the stored one.
func (o *orgbConn) SaveMode(dev orgbDevice, idx int, m orgbMode) error {
	return o.write(dev.Address, pktSaveMode, modePayload(o.version, idx, m))
}

// SetLEDs paints every LED of the device.
func (o *orgbConn) SetLEDs(dev orgbDevice, colors []uint32) error {
	body := make([]byte, 0, 6+4*len(colors))
	body = append(body, u32(uint32(6+4*len(colors)))...)
	body = append(body, u16(uint16(len(colors)))...)
	for _, c := range colors {
		body = append(body, u32(c)...)
	}
	return o.write(dev.Address, pktUpdateLEDs, body)
}

// SetZoneLEDs paints one zone, for a device whose zones the user coloured apart.
func (o *orgbConn) SetZoneLEDs(dev orgbDevice, zone int, colors []uint32) error {
	body := make([]byte, 0, 10+4*len(colors))
	body = append(body, u32(uint32(10+4*len(colors)))...)
	body = append(body, u32(uint32(zone))...)
	body = append(body, u16(uint16(len(colors)))...)
	for _, c := range colors {
		body = append(body, u32(c)...)
	}
	return o.write(dev.Address, pktUpdateZoneLEDs, body)
}

// modePayload serialises one mode in the negotiated controller-description
// layout, prefixed with the packet's own length.
func modePayload(protocol uint32, idx int, m orgbMode) []byte {
	b := make([]byte, 0, 64)
	b = append(b, u32(uint32(idx))...)
	b = append(b, orgbString(m.Name)...)
	if protocol < 6 {
		b = append(b, u32(uint32(m.Value))...)
	}
	for _, v := range []uint32{m.Flags, m.SpeedMin, m.SpeedMax, m.BriMin, m.BriMax,
		m.ColorsMin, m.ColorsMax, m.Speed, m.Bri, m.Direction, m.ColorMode} {
		b = append(b, u32(v)...)
	}
	b = append(b, u16(uint16(len(m.Colors)))...)
	for _, c := range m.Colors {
		b = append(b, u32(c)...)
	}
	return append(u32(uint32(len(b)+4)), b...)
}

// parseDevice reads one controller description in the negotiated wire layout.
func parseDevice(b []byte, protocol uint32) (orgbDevice, error) {
	r := &reader{b: b}
	size := r.u32()
	if int(size) != len(b) {
		return orgbDevice{}, fmt.Errorf("size %d does not match %d bytes", size, len(b))
	}
	var d orgbDevice
	d.Type = orgbTypeName(r.i32())
	d.Name = r.str()
	d.Vendor = r.str()
	d.Description = r.str()
	d.Version = r.str()
	d.Serial = r.str()
	d.Location = r.str()

	modes := int(r.u16())
	d.ActiveMode = int(r.i32())
	for range modes {
		d.Modes = append(d.Modes, parseMode(r, protocol))
	}

	var start uint32
	for range int(r.u16()) {
		z := orgbZone{Name: r.str(), Type: r.i32()}
		r.u32() // minimum LED count
		r.u32() // maximum LED count
		z.LEDs = r.u32()
		z.H, z.W, z.Map = r.matrix(r.u16(), true)
		for range int(r.u16()) {
			r.str()
			r.i32()
			r.u32()
			r.u32()
			if protocol >= 6 {
				r.matrix(r.u16(), false)
				r.u32()
			}
		}
		r.u32() // zone flags
		if protocol >= 6 {
			r.i32() // active zone mode
			for range int(r.u16()) {
				parseMode(r, protocol)
			}
			r.str() // display name
		}
		z.Start = start
		start += z.LEDs
		d.Zones = append(d.Zones, z)
	}

	d.LEDCount = int(r.u16())
	for range d.LEDCount {
		r.str()
		if protocol < 6 {
			r.u32()
		}
	}
	for range int(r.u16()) {
		r.u32() // current LED colour
	}
	for range int(r.u16()) {
		r.str() // alternate LED name
	}
	r.u32() // controller flags
	if protocol >= 6 {
		r.str()   // display name
		r.str32() // device-specific configuration
	}
	if r.err != nil {
		return orgbDevice{}, r.err
	}
	if r.i != len(b) {
		return orgbDevice{}, fmt.Errorf("controller description has %d trailing bytes", len(b)-r.i)
	}
	if d.ActiveMode < 0 || d.ActiveMode >= len(d.Modes) {
		d.ActiveMode = 0
	}
	return d, nil
}

func parseMode(r *reader, protocol uint32) orgbMode {
	var m orgbMode
	m.Name = r.str()
	if protocol < 6 {
		m.Value = r.i32()
	}
	m.Flags = r.u32()
	m.SpeedMin, m.SpeedMax = r.u32(), r.u32()
	m.BriMin, m.BriMax = r.u32(), r.u32()
	m.ColorsMin, m.ColorsMax = r.u32(), r.u32()
	m.Speed, m.Bri = r.u32(), r.u32()
	m.Direction, m.ColorMode = r.u32(), r.u32()
	for range int(r.u16()) {
		m.Colors = append(m.Colors, r.u32())
	}
	return m
}

// reader = a little-endian cursor over a controller description. A short buffer
// records an error instead of panicking, so a protocol change degrades to
// "device unreadable" rather than taking the Hub down.
type reader struct {
	b   []byte
	i   int
	err error
}

func (r *reader) take(n int) []byte {
	if r.err != nil {
		return make([]byte, n)
	}
	if n < 0 || n > len(r.b)-r.i {
		r.err = io.ErrUnexpectedEOF
		return make([]byte, n)
	}
	out := r.b[r.i : r.i+n]
	r.i += n
	return out
}

func (r *reader) u16() uint16 { return binary.LittleEndian.Uint16(r.take(2)) }
func (r *reader) u32() uint32 { return binary.LittleEndian.Uint32(r.take(4)) }
func (r *reader) i32() int32  { return int32(r.u32()) }
func (r *reader) str() string { return r.string(int(r.u16())) }
func (r *reader) str32() string {
	n := r.u32()
	if uint64(n) > uint64(len(r.b)) {
		r.err = io.ErrUnexpectedEOF
		return ""
	}
	return r.string(int(n))
}

func (r *reader) string(n int) string {
	if n == 0 {
		return ""
	}
	s := r.take(n)
	if r.err != nil {
		return ""
	}
	if s[n-1] != 0 {
		r.err = errors.New("openrgb: unterminated string")
		return ""
	}
	return string(s[:n-1])
}

func (r *reader) matrix(size uint16, keep bool) (height, width uint32, values []uint32) {
	if size == 0 {
		return 0, 0, nil
	}
	start := r.i
	height, width = r.u32(), r.u32()
	count := uint64(height) * uint64(width)
	if count > uint64(len(r.b)-r.i)/4 {
		r.err = io.ErrUnexpectedEOF
		return 0, 0, nil
	}
	if keep {
		values = make([]uint32, int(count))
		for i := range values {
			values[i] = r.u32()
		}
	} else {
		r.i += int(count) * 4
	}
	if r.err == nil && r.i-start != int(size) {
		r.err = fmt.Errorf("openrgb: matrix declares %d bytes, used %d", size, r.i-start)
	}
	return height, width, values
}

func u16(v uint16) []byte {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, v)
	return b
}

func u32(v uint32) []byte {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, v)
	return b
}

func orgbString(s string) []byte {
	return append(u16(uint16(len(s)+1)), append([]byte(s), 0)...)
}
