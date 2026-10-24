#pragma once

#include <QString>

#include <memory>

class Layout;

// Aliases: grid is wall, nova is sandy; an unknown key falls back to Slices.
std::unique_ptr<Layout> makeLayout(const QString &mode);
