package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

// Returned before the file exists so the picker can bind to it; the image arrives later.
func (s *sources) remoteThumbPath(source, id, thumbURL string) string {
	ext := safeSeg(extFromURL(thumbURL))
	return filepath.Join(s.d.config().cacheDir(), "remote", safeSeg(source), safeSeg(id)+"."+ext)
}

func (d *daemon) remoteThumbPath(source, id, thumbURL string) string {
	return d.sources.remoteThumbPath(source, id, thumbURL)
}

func (d *daemon) queueRemoteThumbs(connectionID uint64, searchSource, source string, generation int64, jobs [][2]string) {
	d.sources.queueRemoteThumbs(connectionID, searchSource, source, generation, jobs)
}

func (s *sources) queueRemoteThumbs(connectionID uint64, searchSource, source string, generation int64, jobs [][2]string) {
	if len(jobs) == 0 {
		return
	}
	go func() {
		for _, job := range jobs {
			if !s.thumbGenerationCurrent(connectionID, searchSource, generation) {
				return
			}
			id, thumbURL := job[0], job[1]
			if id == "" || thumbURL == "" {
				continue
			}
			dest := s.remoteThumbPath(source, id, thumbURL)
			inflightKey := "thumb:" + dest
			if !s.beginInflight(inflightKey) {
				continue
			}
			s.thumbSem <- struct{}{}
			if !s.thumbGenerationCurrent(connectionID, searchSource, generation) {
				<-s.thumbSem
				s.endInflight(inflightKey)
				return
			}
			go func(id, thumbURL, dest, inflightKey string) {
				defer func() { <-s.thumbSem }()
				defer s.endInflight(inflightKey)
				s.fetchThumb(source, id, thumbURL, dest)
			}(id, thumbURL, dest, inflightKey)
		}
	}()
}

func (s *sources) fetchThumb(source, id, thumbURL, dest string) {
	if fi, err := os.Stat(dest); err == nil && fi.Size() > 0 {
		s.d.broadcast(evRemoteThumb, map[string]interface{}{"source": source, "id": id, "path": dest})
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), thumbFetchTimeout)
	defer cancel()
	policy := func(u string) error { return requireSource(source, u) }
	if err := s.fetchToFile(ctx, thumbURL, dest, sniffImage, previewMaxEncoded, policy, nil); err != nil {
		fmt.Fprintf(os.Stderr, "ryogami: thumb %s/%s: %v\n", source, id, err)
		return
	}
	s.d.broadcast(evRemoteThumb, map[string]interface{}{"source": source, "id": id, "path": dest})
}
