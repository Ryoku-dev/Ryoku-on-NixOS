package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fixtureController(t *testing.T, protocol uint32) ([]byte, orgbDevice) {
	t.Helper()
	path := filepath.Join("testdata", fmt.Sprintf("openrgb-v%d-controller.hex", protocol))
	text, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	data, err := hex.DecodeString(strings.TrimSpace(string(text)))
	if err != nil {
		t.Fatal(err)
	}
	device, err := parseDevice(data, protocol)
	if err != nil {
		t.Fatalf("parse protocol %d fixture: %v", protocol, err)
	}
	return data, device
}

func TestControllerFixturesParseAndEncode(t *testing.T) {
	cases := []struct {
		protocol uint32
		size     int
		payload  string
	}{
		{5, 620, "43000000000000000700446972656374000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000"},
		{6, 1220, "3f0000000000000007004469726563740020000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000"},
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("v%d", tc.protocol), func(t *testing.T) {
			raw, device := fixtureController(t, tc.protocol)
			if len(raw) != tc.size {
				t.Fatalf("fixture length = %d, want %d", len(raw), tc.size)
			}
			if device.Name != "Distro Debug Keyboard" || device.Serial != "Debug Keyboard Serial String" {
				t.Fatalf("identity = %q / %q", device.Name, device.Serial)
			}
			if len(device.Modes) != 1 || device.Modes[0].Name != "Direct" {
				t.Fatalf("modes = %+v", device.Modes)
			}
			if len(device.Zones) != 2 || device.Zones[0].LEDs != 1 || device.Zones[1].LEDs != 10 {
				t.Fatalf("zones = %+v", device.Zones)
			}
			if device.Zones[1].Start != 1 || device.LEDCount != 11 {
				t.Fatalf("layout: second zone starts at %d, LEDs = %d", device.Zones[1].Start, device.LEDCount)
			}
			want, err := hex.DecodeString(tc.payload)
			if err != nil {
				t.Fatal(err)
			}
			got := modePayload(tc.protocol, 0, device.Modes[0])
			if !bytes.Equal(got, want) {
				t.Fatalf("mode payload = %x, want %x", got, want)
			}
		})
	}
}

type wirePacket struct {
	device uint32
	id     uint32
	body   []byte
}

func readWirePacket(r io.Reader) (wirePacket, error) {
	header := make([]byte, 16)
	if _, err := io.ReadFull(r, header); err != nil {
		return wirePacket{}, err
	}
	if string(header[:4]) != "ORGB" {
		return wirePacket{}, fmt.Errorf("bad magic %q", header[:4])
	}
	packet := wirePacket{
		device: binary.LittleEndian.Uint32(header[4:]),
		id:     binary.LittleEndian.Uint32(header[8:]),
		body:   make([]byte, binary.LittleEndian.Uint32(header[12:])),
	}
	_, err := io.ReadFull(r, packet.body)
	return packet, err
}

func wireBytes(device, id uint32, body []byte) []byte {
	packet := make([]byte, 16+len(body))
	copy(packet, "ORGB")
	binary.LittleEndian.PutUint32(packet[4:], device)
	binary.LittleEndian.PutUint32(packet[8:], id)
	binary.LittleEndian.PutUint32(packet[12:], uint32(len(body)))
	copy(packet[16:], body)
	return packet
}

func captureWrite(t *testing.T, protocol uint32, run func(*orgbConn) error) wirePacket {
	t.Helper()
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	result := make(chan struct {
		packet wirePacket
		err    error
	}, 1)
	go func() {
		packet, err := readWirePacket(server)
		if err == nil && protocol >= 6 {
			stale := append(u32(pktControllerCount), u32(0)...)
			ack := append(u32(packet.id), u32(0)...)
			_, err = server.Write(append(wireBytes(0, pktAck, stale), wireBytes(packet.device, pktAck, ack)...))
		}
		result <- struct {
			packet wirePacket
			err    error
		}{packet, err}
	}()

	conn := &orgbConn{c: client, dur: time.Second, version: protocol}
	if err := run(conn); err != nil {
		t.Fatalf("write: %v", err)
	}
	got := <-result
	if got.err != nil {
		t.Fatalf("server: %v", got.err)
	}
	return got.packet
}

func TestWritesUseNegotiatedDeviceAddress(t *testing.T) {
	for _, protocol := range []uint32{5, 6} {
		t.Run(fmt.Sprintf("v%d", protocol), func(t *testing.T) {
			fixture, _ := fixtureController(t, protocol)
			wantAddress := uint32(0)
			count := u32(1)
			if protocol >= 6 {
				wantAddress = 37
				count = append(count, u32(wantAddress)...)
			}

			client, server := net.Pipe()
			defer client.Close()
			defer server.Close()
			result := make(chan struct {
				data, update wirePacket
				err          error
			}, 1)
			go func() {
				var got struct {
					data, update wirePacket
					err          error
				}
				if _, got.err = readWirePacket(server); got.err == nil {
					_, got.err = server.Write(wireBytes(0, pktControllerCount, count))
				}
				if got.err == nil {
					got.data, got.err = readWirePacket(server)
				}
				if got.err == nil {
					_, got.err = server.Write(wireBytes(wantAddress, pktControllerData, fixture))
				}
				if got.err == nil {
					got.update, got.err = readWirePacket(server)
				}
				if got.err == nil && protocol >= 6 {
					ack := append(u32(got.update.id), u32(0)...)
					_, got.err = server.Write(wireBytes(got.update.device, pktAck, ack))
				}
				result <- got
			}()

			conn := &orgbConn{c: client, dur: time.Second, version: protocol}
			devices, err := conn.Devices()
			if err != nil {
				t.Fatal(err)
			}
			if len(devices) != 1 || devices[0].Index != 0 || devices[0].Address != wantAddress {
				t.Fatalf("enumerated device = %+v", devices)
			}
			if err := conn.SetMode(devices[0], 0, devices[0].Modes[0]); err != nil {
				t.Fatal(err)
			}
			got := <-result
			if got.err != nil {
				t.Fatal(got.err)
			}
			if got.data.device != wantAddress || got.data.id != pktControllerData {
				t.Fatalf("data request address/id = %d/%d, want %d/%d", got.data.device, got.data.id, wantAddress, pktControllerData)
			}
			if protocol < 6 && !bytes.Equal(got.data.body, u32(5)) {
				t.Fatalf("v5 data request body = %x", got.data.body)
			}
			if protocol >= 6 && len(got.data.body) != 0 {
				t.Fatalf("v6 data request body = %x", got.data.body)
			}
			if got.update.device != wantAddress || got.update.id != pktUpdateMode {
				t.Fatalf("write address/id = %d/%d, want %d/%d", got.update.device, got.update.id, wantAddress, pktUpdateMode)
			}
		})
	}
}

func TestLEDAndZonePayloads(t *testing.T) {
	device := orgbDevice{Address: 9}
	leds := captureWrite(t, 6, func(conn *orgbConn) error {
		return conn.SetLEDs(device, []uint32{0x112233})
	})
	if got := hex.EncodeToString(leds.body); got != "0a000000010033221100" {
		t.Fatalf("LED payload = %s", got)
	}
	zone := captureWrite(t, 6, func(conn *orgbConn) error {
		return conn.SetZoneLEDs(device, 3, []uint32{0x112233, 0x445566})
	})
	if got := hex.EncodeToString(zone.body); got != "120000000300000002003322110066554400" {
		t.Fatalf("zone payload = %s", got)
	}
}

func TestReplySkipsAcknowledgementForAnotherPacket(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()

	go func() {
		ack := append(u32(pktClientName), u32(0)...)
		packets := append(wireBytes(0, pktAck, ack), wireBytes(0, pktControllerCount, u32(3))...)
		_, _ = server.Write(packets)
	}()

	conn := &orgbConn{c: client, dur: time.Second, version: 6}
	body, err := conn.reply(pktControllerCount)
	if err != nil {
		t.Fatal(err)
	}
	if len(body) != 4 || binary.LittleEndian.Uint32(body) != 3 {
		t.Fatalf("reply body = %x", body)
	}
}
