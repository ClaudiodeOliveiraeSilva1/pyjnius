activeLambdaJavaProxies = set()

cdef jstringy_arg(argtype):
    return argtype in ('Ljava/lang/String;',
                       'Ljava/lang/CharSequence;',
                       'Ljava/lang/Object;')

cdef void release_args(JNIEnv *j_env, tuple definition_args, pass_by_reference, jvalue *j_args, args) except *:
    # do the conversion from a Python object to Java from a Java definition
    cdef JavaObject jo
    cdef JavaClass jc
    cdef int index
    cdef int last_pass_by_ref_index

    last_pass_by_ref_index = len(pass_by_reference) - 1

    for index, argtype in enumerate(definition_args):
        py_arg = args[index]
        if argtype[0] == 'L':
            if py_arg is None:
                j_args[index].l = NULL
            if isinstance(py_arg, basestring) and \
                    jstringy_arg(argtype):
                j_env[0].DeleteLocalRef(j_env, j_args[index].l)
        elif argtype[0] == '[':
            if pass_by_reference[min(index, last_pass_by_ref_index)] and hasattr(args[index], '__setitem__'):
                ret = convert_jarray_to_python(j_env, argtype[1:], j_args[index].l)
                try:
                    args[index][:] = ret
                except TypeError:
                    pass
            j_env[0].DeleteLocalRef(j_env, j_args[index].l)

cdef void populate_args(JNIEnv *j_env, tuple definition_args, jvalue *j_args, args) except *:
    # do the conversion from a Python object to Java from a Java definition
    cdef JavaClassStorage jcs
    cdef JavaObject jo
    cdef JavaClass jc
    cdef PythonJavaClass pc
    cdef int index

    for index, argtype in enumerate(definition_args):
        py_arg = args[index]
        if argtype == 'Z':
            j_args[index].z = py_arg
        elif argtype == 'B':
            j_args[index].b = py_arg
        elif argtype == 'C':
            j_args[index].c = ord(py_arg)
        elif argtype == 'S':
            j_args[index].s = py_arg
        elif argtype == 'I':
            j_args[index].i = py_arg
        elif argtype == 'J':
            j_args[index].j = py_arg
        elif argtype == 'F':
            j_args[index].f = py_arg
        elif argtype == 'D':
            j_args[index].d = py_arg
        elif argtype[0] == 'L':
            if py_arg is None:
                j_args[index].l = NULL

            # numeric types
            elif isinstance(py_arg, int):
                j_args[index].l = convert_python_to_jobject(
                    j_env, 'Ljava/lang/Integer;', py_arg
                )
                check_assignable_from_str(j_env, 'java/lang/Integer', argtype[1:-1])
            elif isinstance(py_arg, float):
                j_args[index].l = convert_python_to_jobject(
                    j_env, 'Ljava/lang/Float;', py_arg
                )
                check_assignable_from_str(j_env, 'java/lang/Float', argtype[1:-1])
            # string types
            elif isinstance(py_arg, base_string) and jstringy_arg(argtype):
                j_args[index].l = convert_pystr_to_java(
                    j_env, to_unicode(py_arg)
                )
                check_assignable_from_str(j_env, 'java/lang/String', argtype[1:-1])
            elif isinstance(py_arg, JavaClass):
                jc = py_arg
                check_assignable_from(j_env, jc, argtype[1:-1])
                j_args[index].l = jc.j_self.obj

            # objects
            elif isinstance(py_arg, JavaObject):
                jo = py_arg
                j_args[index].l = jo.obj
            elif isinstance(py_arg, MetaJavaClass):
                jcs = getattr(py_arg, CLS_STORAGE_NAME)
                j_args[index].l = jcs.j_cls
            elif isinstance(py_arg, PythonJavaClass):
                # from python class, get the proxy/python class
                pc = py_arg
                # get the java class
                jc = pc.j_self
                if jc is None:
                    pc._init_j_self_ptr()
                    jc = pc.j_self
                # get the localref
                j_args[index].l = jc.j_self.obj

            # implementation of Java class in Python (needs j_cls)
            elif isinstance(py_arg, type):
                jc = py_arg
                j_args[index].l = jc.j_cls

            # array
            elif isinstance(py_arg, (tuple, list)):
                j_args[index].l = convert_pyarray_to_java(j_env, argtype, py_arg)

            # lambda or function
            elif callable(py_arg):
                
                # we need to make a java object in python
                py_arg = convert_python_callable_to_jobject(argtype, py_arg)

                # TODO: this line should not be needed to prevent py_arg from being GCd 
                activeLambdaJavaProxies.add(py_arg)
                
                # next few lines is from "isinstance(py_arg, PythonJavaClass)" above
                # except jc is None is removed, as we know it has been called by
                # convert_python_callable_to_jobject()

                # from python class, get the proxy/python class
                pc = py_arg
                # get the java class
                jc = pc.j_self

                # get the localref
                j_args[index].l = jc.j_self.obj

            else:
                raise JavaException('Invalid python object for this '
                        'argument. Want {0!r}, got {1!r}'.format(
                            argtype[1:-1], py_arg))

        elif argtype[0] == '[':
            if py_arg is None:
                j_args[index].l = NULL
                continue
            if isinstance(py_arg, str) and argtype == '[C':
                py_arg = list(py_arg)
            if isinstance(py_arg, ByteArray) and argtype != '[B':
                raise JavaException(
                    'Cannot use ByteArray for signature {}'.format(argtype))
            if not isinstance(py_arg, (list, tuple, ByteArray, bytes, bytearray)):
                raise JavaException('Expecting a python list/tuple, got '
                        '{0!r}'.format(py_arg))
            j_args[index].l = convert_pyarray_to_java(
                    j_env, argtype[1:], py_arg)


cdef convert_jobject_to_python(JNIEnv *j_env, definition, jobject j_object):
    # ... código inalterado ...


def get_signature(cls_tp):
    # ... código inalterado ...


def get_param_signature(m):
    # ... código inalterado ...


def convert_python_callable_to_jobject(definition, pyarg):
    # ... código inalterado ...


cdef jobject convert_python_to_jobject(JNIEnv *j_env, definition, obj) except *:
    cdef jobject retobject, retsubobject
    cdef jclass retclass
    cdef jmethodID redmidinit = NULL
    cdef jvalue j_ret[1]
    cdef JavaClass jc
    cdef JavaObject jo
    cdef JavaClassStorage jcs
    cdef PythonJavaClass pc
    cdef int index

    if definition[0] == 'V':
        return NULL
    elif definition[0] == 'L':
        if obj is None:
            return NULL

        # string types
        elif isinstance(obj, base_string) and jstringy_arg(definition):
            return convert_pystr_to_java(j_env, to_unicode(obj))

        # numeric types
        elif isinstance(obj, int) and \
                definition in (
                    'Ljava/lang/Integer;',
                    'Ljava/lang/Number;',
                    'Ljava/lang/Long;',
                    'Ljava/lang/Object;'):
            j_ret[0].i = int(obj)
            retclass = j_env[0].FindClass(j_env, 'java/lang/Integer')
            retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(I)V')
            retobject = j_env[0].NewObjectA(j_env, retclass, retmidinit, j_ret)
            return retobject
        elif isinstance(obj, float) and \
                definition in (
                    'Ljava/lang/Float;',
                    'Ljava/lang/Number;',
                    'Ljava/lang/Object;'):
            j_ret[0].f = obj
            retclass = j_env[0].FindClass(j_env, 'java/lang/Float')
            retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(F)V')
            retobject = j_env[0].NewObjectA(j_env, retclass, retmidinit, j_ret)
            return retobject

        # implementation of Java class in Python (needs j_cls)
        elif isinstance(obj, type):
            jc = obj
            return jc.j_cls

        # objects
        elif isinstance(obj, JavaClass):
            jc = obj
            check_assignable_from(j_env, jc, definition[1:-1])
            return jc.j_self.obj
        elif isinstance(obj, JavaObject):
            jo = obj
            return jo.obj
        elif isinstance(obj, MetaJavaClass):
            jcs = getattr(obj, CLS_STORAGE_NAME)
            return jcs.j_cls
        elif isinstance(obj, PythonJavaClass):
            # from python class, get the proxy/python class
            pc = obj
            # get the java class
            jc = pc.j_self
            if jc is None:
                pc._init_j_self_ptr()
                jc = pc.j_self
            # get the localref
            return jc.j_self.obj

        # array
        elif isinstance(obj, (tuple, list)):
            return convert_pyarray_to_java(j_env, definition, obj)

        else:
            raise JavaException('Invalid python object for this '
                    'argument. Want {0!r}, got {1!r}'.format(
                        definition[1:-1], obj))

    elif definition[0] == '[':
        conversions = {
            int: 'I',
            bool: 'Z',
            float: 'F',
            unicode: 'Ljava/lang/String;',
            bytes: 'B'
        }
        retclass = j_env[0].FindClass(j_env, 'java/lang/Object')
        retobject = j_env[0].NewObjectArray(j_env, len(obj), retclass, NULL)
        for index, item in enumerate(obj):
            item_definition = conversions.get(type(item), definition[1:])
            retsubobject = convert_python_to_jobject(
                    j_env, item_definition, item)
            j_env[0].SetObjectArrayElement(j_env, retobject, index,
                    retsubobject)
            j_env[0].DeleteLocalRef(j_env, retsubobject)
        return retobject

    elif definition == 'B':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Byte')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(B)V')
        j_ret[0].b = obj
    elif definition == 'S':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Short')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(S)V')
        j_ret[0].s = obj
    elif definition == 'I':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Integer')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(I)V')
        j_ret[0].i = int(obj)
    elif definition == 'J':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Long')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(J)V')
        j_ret[0].j = obj
    elif definition == 'F':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Float')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(F)V')
        j_ret[0].f = obj
    elif definition == 'D':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Double')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(D)V')
        j_ret[0].d = obj
    elif definition == 'C':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Char')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(C)V')
        j_ret[0].c = ord(obj)
    elif definition == 'Z':
        retclass = j_env[0].FindClass(j_env, 'java/lang/Boolean')
        retmidinit = j_env[0].GetMethodID(j_env, retclass, '<init>', '(Z)V')
        j_ret[0].z = 1 if obj else 0
    else:
        assert(0)

    assert(retclass != NULL)
    # XXX do we need a globalref or something ?
    retobject = j_env[0].NewObjectA(j_env, retclass, retmidinit, j_ret)
    return retobject

cdef jstring convert_pystr_to_java(JNIEnv *j_env, unicode py_uni) except NULL:
    # ... código inalterado ...


cdef jobject convert_pyarray_to_java(JNIEnv *j_env, definition, pyarray) except *:
    cdef jobject ret = NULL
    cdef jobject nested = NULL
    cdef int array_size = len(pyarray)
    cdef int i
    cdef unsigned char c_tmp
    cdef jboolean j_boolean
    cdef jbyte j_byte
    cdef const_jbyte* j_bytes
    cdef jchar j_char
    cdef jshort j_short
    cdef jint j_int
    cdef jlong j_long
    cdef jfloat j_float
    cdef jdouble j_double
    cdef jstring j_string
    cdef jclass j_class
    cdef JavaObject jo
    cdef JavaClass jc

    cdef ByteArray a_bytes

    if definition == 'Ljava/lang/Object;' and len(pyarray) > 0:
        # then the method will accept any array type as param
        # let's be as precise as we can
        conversions = {
            int: 'I',
            bool: 'Z',
            float: 'F',
            bytes: 'B',
            str: 'Ljava/lang/String;',
        }
        for _type, override in conversions.items():
            if isinstance(pyarray[0], _type):
                definition = override
                break

    if definition == 'Z':
        ret = j_env[0].NewBooleanArray(j_env, array_size)
        for i in range(array_size):
            j_boolean = 1 if pyarray[i] else 0
            j_env[0].SetBooleanArrayRegion(j_env,
                    ret, i, 1, &j_boolean)

    elif definition == 'B':
        ret = j_env[0].NewByteArray(j_env, array_size)
        if isinstance(pyarray, ByteArray):
            a_bytes = pyarray
            j_env[0].SetByteArrayRegion(j_env,
                ret, 0, array_size, <const_jbyte *>a_bytes._buf)
        elif isinstance(pyarray, (bytearray, bytes)):
            j_bytes = <signed char *>pyarray
            j_env[0].SetByteArrayRegion(j_env,
                ret, 0, array_size, j_bytes)
        else:
            for i in range(array_size):
                c_tmp = pyarray[i]
                j_byte = <signed char>c_tmp
                j_env[0].SetByteArrayRegion(j_env,
                        ret, i, 1, &j_byte)

    elif definition == 'C':
        ret = j_env[0].NewCharArray(j_env, array_size)
        for i in range(array_size):
            j_char = ord(pyarray[i])
            j_env[0].SetCharArrayRegion(j_env,
                    ret, i, 1, &j_char)

    elif definition == 'S':
        ret = j_env[0].NewShortArray(j_env, array_size)
        for i in range(array_size):
            j_short = pyarray[i]
            j_env[0].SetShortArrayRegion(j_env,
                    ret, i, 1, &j_short)

    elif definition == 'I':
        ret = j_env[0].NewIntArray(j_env, array_size)
        for i in range(array_size):
            j_int = pyarray[i]
            j_env[0].SetIntArrayRegion(j_env,
                    ret, i, 1, <const_jint *>&j_int)

    elif definition == 'J':
        ret = j_env[0].NewLongArray(j_env, array_size)
        for i in range(array_size):
            j_long = pyarray[i]
            j_env[0].SetLongArrayRegion(j_env,
                    ret, i, 1, &j_long)

    elif definition == 'F':
        ret = j_env[0].NewFloatArray(j_env, array_size)
        for i in range(array_size):
            j_float = pyarray[i]
            j_env[0].SetFloatArrayRegion(j_env,
                    ret, i, 1, &j_float)

    elif definition == 'D':
        ret = j_env[0].NewDoubleArray(j_env, array_size)
        for i in range(array_size):
            j_double = pyarray[i]
            j_env[0].SetDoubleArrayRegion(j_env,
                    ret, i, 1, &j_double)

    elif definition[0] == 'L':
        defstr = str_for_c(definition[1:-1])
        j_class = j_env[0].FindClass(j_env, <bytes>defstr)

        if j_class == NULL:
            raise JavaException(
                'Cannot create array with a class not '
                'found {0!r}'.format(definition[1:-1])
            )

        ret = j_env[0].NewObjectArray(
            j_env, array_size, j_class, NULL
        )

        # iterate over each Python array element
        # and add it to Object[].
        for i in range(array_size):
            arg = pyarray[i]

            if arg is None:
                j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, i, NULL
                )

            elif isinstance(arg, basestring):
                j_string = convert_pystr_to_java(j_env, to_unicode(arg))
                j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, i, j_string
                )
                j_env[0].DeleteLocalRef(j_env, j_string)

            # isinstance(arg, type) will return False
            # ...and it's really weird
            elif isinstance(arg, (tuple, list)):
                nested = convert_pyarray_to_java(
                    j_env, definition, arg
                )
                j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, i, nested
                )
                j_env[0].DeleteLocalRef(j_env, nested)

            # no local refs to delete for class, type and object
            elif isinstance(arg, JavaClass):
                jc = arg
                check_assignable_from(j_env, jc, definition[1:-1])
                j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, i, jc.j_self.obj
                )

            elif isinstance(arg, type):
                jc = arg
                j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, i, jc.j_cls
                )

            elif isinstance(arg, JavaObject):
                jo = arg
                j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, i, jo.obj
                )

            else:
                raise JavaException(
                    'Invalid variable {!r} used for L array {!r}'.format(
                        pyarray, definition
                    )
                )

    elif definition[0] == '[':
        subdef = definition[1:]
        eproto = convert_pyarray_to_java(j_env, subdef, pyarray[0])
        ret = j_env[0].NewObjectArray(
                j_env, array_size, j_env[0].GetObjectClass(j_env, eproto), NULL)
        j_env[0].SetObjectArrayElement(
                    j_env, <jobjectArray>ret, 0, eproto)
        j_env[0].DeleteLocalRef(j_env, eproto)
        for i in range(1, array_size):
            j_elem = convert_pyarray_to_java(j_env, subdef, pyarray[i])
            j_env[0].SetObjectArrayElement(j_env, <jobjectArray>ret, i, j_elem)
            j_env[0].DeleteLocalRef(j_env, j_elem)

    else:
        raise JavaException(
            'Invalid array definition {!r} for variable {!r}'.format(
                definition, pyarray
            )
        )

    return <jobject>ret
