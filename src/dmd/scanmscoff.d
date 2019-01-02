/**
 * Compiler implementation of the
 * $(LINK2 http://www.dlang.org, D programming language).
 *
 * Copyright:   Copyright (C) 1999-2019 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/scanmscoff.d, _scanmscoff.d)
 * Documentation:  https://dlang.org/phobos/dmd_scanmscoff.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/scanmscoff.d
 */

module dmd.scanmscoff;

version(Windows):

import core.stdc.string, core.stdc.stdlib, core.sys.windows.winnt;
import dmd.globals, dmd.errors;

enum LOG = false;

/*****************************************
 * Reads an object module from base[] and passes the names
 * of any exported symbols to (*pAddSymbol)().
 * Params:
 *      pAddSymbol =  function to pass the names to
 *      base =        array of contents of object module
 *      module_name = name of the object module (used for error messages)
 *      loc =         location to use for error printing
 */
void scanMSCoffObjModule(void delegate(const(char)[] name, int pickAny) pAddSymbol,
        const(ubyte)[] base, const(char)* module_name, Loc loc)
{
    static if (LOG)
    {
        printf("scanMSCoffObjModule(%s)\n", module_name);
    }

    void corrupt(int reason)
    {
        error(loc, "corrupt MS-Coff object module `%s` %d", module_name, reason);
    }

    const buf = base.ptr;
    const buflen = base.length;
    /* First do sanity checks on object file
     */
    if (buflen < BIGOBJ_HEADER.sizeof)
        return corrupt(__LINE__);

    BIGOBJ_HEADER* header = cast(BIGOBJ_HEADER*)buf;
    char is_old_coff = false;
    if (header.Sig2 != 0xFFFF && header.Version != 2)
    {
        is_old_coff = true;
        IMAGE_FILE_HEADER* header_old;
        header_old = cast(IMAGE_FILE_HEADER*)malloc(IMAGE_FILE_HEADER.sizeof);
        memcpy(header_old, buf, IMAGE_FILE_HEADER.sizeof);
        header = cast(BIGOBJ_HEADER*)malloc(BIGOBJ_HEADER.sizeof);
        *header = BIGOBJ_HEADER.init;
        header.Machine = header_old.Machine;
        header.NumberOfSections = header_old.NumberOfSections;
        header.TimeDateStamp = header_old.TimeDateStamp;
        header.PointerToSymbolTable = header_old.PointerToSymbolTable;
        header.NumberOfSymbols = header_old.NumberOfSymbols;
        free(header_old);
    }
    switch (header.Machine)
    {
    case IMAGE_FILE_MACHINE_UNKNOWN:
    case IMAGE_FILE_MACHINE_I386:
    case IMAGE_FILE_MACHINE_AMD64:
        break;
    default:
        if (buf[0] == 0x80)
            error(loc, "Object module `%s` is 32 bit OMF, but it should be 64 bit MS-Coff", module_name);
        else
            error(loc, "MS-Coff object module `%s` has magic = %x, should be %x", module_name, header.Machine, IMAGE_FILE_MACHINE_AMD64);
        return;
    }
    // Get string table:  string_table[0..string_len]
    size_t off = header.PointerToSymbolTable;
    if (off == 0)
    {
        error(loc, "MS-Coff object module `%s` has no string table", module_name);
        return;
    }
    off += header.NumberOfSymbols * (is_old_coff ? SymbolTable.sizeof : SymbolTable32.sizeof);
    if (off + 4 > buflen)
        return corrupt(__LINE__);

    uint string_len = *cast(uint*)(buf + off);
    char* string_table = cast(char*)(buf + off + 4);
    if (off + string_len > buflen)
        return corrupt(__LINE__);

    string_len -= 4;
    for (int i = 0; i < header.NumberOfSymbols; i++)
    {
        SymbolTable32* n;
        char[8 + 1] s;
        char* p;
        static if (LOG)
        {
            printf("Symbol %d:\n", i);
        }
        off = header.PointerToSymbolTable + i * (is_old_coff ? SymbolTable.sizeof : SymbolTable32.sizeof);
        if (off > buflen)
            return corrupt(__LINE__);

        n = cast(SymbolTable32*)(buf + off);
        if (is_old_coff)
        {
            SymbolTable* n2;
            n2 = cast(SymbolTable*)malloc(SymbolTable.sizeof);
            memcpy(n2, (buf + off), SymbolTable.sizeof);
            n = cast(SymbolTable32*)malloc(SymbolTable32.sizeof);
            memcpy(n, n2, (n2.Name).sizeof);
            n.Value = n2.Value;
            n.SectionNumber = n2.SectionNumber;
            n.Type = n2.Type;
            n.StorageClass = n2.StorageClass;
            n.NumberOfAuxSymbols = n2.NumberOfAuxSymbols;
            free(n2);
        }
        if (n.Zeros)
        {
            strncpy(s.ptr, cast(const(char)*)n.Name, 8);
            s[SYMNMLEN] = 0;
            p = s.ptr;
        }
        else
            p = string_table + n.Offset - 4;
        i += n.NumberOfAuxSymbols;
        static if (LOG)
        {
            printf("n_name    = '%s'\n", p);
            printf("n_value   = x%08lx\n", n.Value);
            printf("n_scnum   = %d\n", n.SectionNumber);
            printf("n_type    = x%04x\n", n.Type);
            printf("n_sclass  = %d\n", n.StorageClass);
            printf("n_numaux  = %d\n", n.NumberOfAuxSymbols);
        }
        switch (n.SectionNumber)
        {
        case IMAGE_SYM_DEBUG:
            continue;
        case IMAGE_SYM_ABSOLUTE:
            if (strcmp(p, "@comp.id") == 0)
                continue;
            break;
        case IMAGE_SYM_UNDEFINED:
            // A non-zero value indicates a common block
            if (n.Value)
                break;
            continue;
        default:
            break;
        }
        switch (n.StorageClass)
        {
        case IMAGE_SYM_CLASS_EXTERNAL:
            break;
        case IMAGE_SYM_CLASS_STATIC:
            if (n.Value == 0) // if it's a section name
                continue;
            continue;
        case IMAGE_SYM_CLASS_FUNCTION:
        case IMAGE_SYM_CLASS_FILE:
        case IMAGE_SYM_CLASS_LABEL:
            continue;
        default:
            continue;
        }
        pAddSymbol(p[0 .. strlen(p)], 1);
    }
}

align(1)
struct BIGOBJ_HEADER
{
    WORD Sig1;                  // IMAGE_FILE_MACHINE_UNKNOWN
    WORD Sig2;                  // 0xFFFF
    WORD Version;               // 2
    WORD Machine;               // identifies type of target machine
    DWORD TimeDateStamp;        // creation date, number of seconds since 1970
    BYTE[16]  UUID;             //  { '\xc7', '\xa1', '\xba', '\xd1', '\xee', '\xba', '\xa9', '\x4b',
                                //    '\xaf', '\x20', '\xfa', '\xf6', '\x6a', '\xa4', '\xdc', '\xb8' };
    DWORD[4] unused;            // { 0, 0, 0, 0 }
    DWORD NumberOfSections;     // number of sections
    DWORD PointerToSymbolTable; // file offset of symbol table
    DWORD NumberOfSymbols;      // number of entries in the symbol table
}

align(1)
struct IMAGE_FILE_HEADER
{
    WORD  Machine;
    WORD  NumberOfSections;
    DWORD TimeDateStamp;
    DWORD PointerToSymbolTable;
    DWORD NumberOfSymbols;
    WORD  SizeOfOptionalHeader;
    WORD  Characteristics;
}

enum SYMNMLEN = 8;

enum IMAGE_FILE_MACHINE_UNKNOWN = 0;            // applies to any machine type
enum IMAGE_FILE_MACHINE_I386    = 0x14C;        // x86
enum IMAGE_FILE_MACHINE_AMD64   = 0x8664;       // x86_64

enum IMAGE_SYM_DEBUG     = -2;
enum IMAGE_SYM_ABSOLUTE  = -1;
enum IMAGE_SYM_UNDEFINED = 0;

enum IMAGE_SYM_CLASS_EXTERNAL = 2;
enum IMAGE_SYM_CLASS_STATIC   = 3;
enum IMAGE_SYM_CLASS_LABEL    = 6;
enum IMAGE_SYM_CLASS_FUNCTION = 101;
enum IMAGE_SYM_CLASS_FILE     = 103;

align(1) struct SymbolTable32
{
    union
    {
        BYTE[SYMNMLEN] Name;
        struct
        {
            DWORD Zeros;
            DWORD Offset;
        }
    }

    DWORD Value;
    DWORD SectionNumber;
    WORD Type;
    BYTE StorageClass;
    BYTE NumberOfAuxSymbols;
}

align(1) struct SymbolTable
{
    BYTE[SYMNMLEN] Name;
    DWORD Value;
    WORD SectionNumber;
    WORD Type;
    BYTE StorageClass;
    BYTE NumberOfAuxSymbols;
}
