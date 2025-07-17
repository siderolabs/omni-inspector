// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Package logging implements gRPC logging wrapper.
package logging

import (
	"log"
	"net/http"

	"github.com/felixge/httpsnoop"
)

// Handler adds structured logging to each request going through a wrapped handler.
type Handler struct {
	h http.Handler
}

// ServeHTTP implements http.Handler.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	metrics := httpsnoop.CaptureMetrics(h.h, w, r)

	log.Printf("%s request, url: %s, duration: %s, status: %d",
		r.Method,
		r.RequestURI,
		metrics.Duration,
		metrics.Code,
	)
}

// NewHandler creates new Handler.
func NewHandler(h http.Handler) *Handler {
	return &Handler{h: h}
}
