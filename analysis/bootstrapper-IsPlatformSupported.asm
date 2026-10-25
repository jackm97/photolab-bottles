  409d20:	8b 50 fc             	mov    edx,DWORD PTR [eax-0x4]
  409d23:	83 c1 23             	add    ecx,0x23
  409d26:	2b c2                	sub    eax,edx
  409d28:	83 c0 fc             	add    eax,0xfffffffc
  409d2b:	83 f8 1f             	cmp    eax,0x1f
  409d2e:	0f 87 25 02 00 00    	ja     0x409f59
  409d34:	8b c2                	mov    eax,edx
  409d36:	51                   	push   ecx
  409d37:	50                   	push   eax
  409d38:	e8 33 2a 15 00       	call   0x55c770
  409d3d:	83 c4 08             	add    esp,0x8
  409d40:	8b 4d ec             	mov    ecx,DWORD PTR [ebp-0x14]
  409d43:	33 c0                	xor    eax,eax
  409d45:	c7 45 d0 00 00 00 00 	mov    DWORD PTR [ebp-0x30],0x0
  409d4c:	c7 45 d4 07 00 00 00 	mov    DWORD PTR [ebp-0x2c],0x7
  409d53:	66 89 45 c0          	mov    WORD PTR [ebp-0x40],ax
  409d57:	83 f9 07             	cmp    ecx,0x7
  409d5a:	76 32                	jbe    0x409d8e
  409d5c:	8b 45 d8             	mov    eax,DWORD PTR [ebp-0x28]
  409d5f:	8d 0c 4d 02 00 00 00 	lea    ecx,[ecx*2+0x2]
  409d66:	81 f9 00 10 00 00    	cmp    ecx,0x1000
  409d6c:	72 16                	jb     0x409d84
  409d6e:	8b 50 fc             	mov    edx,DWORD PTR [eax-0x4]
  409d71:	83 c1 23             	add    ecx,0x23
  409d74:	2b c2                	sub    eax,edx
  409d76:	83 c0 fc             	add    eax,0xfffffffc
  409d79:	83 f8 1f             	cmp    eax,0x1f
  409d7c:	0f 87 d7 01 00 00    	ja     0x409f59
  409d82:	8b c2                	mov    eax,edx
  409d84:	51                   	push   ecx
  409d85:	50                   	push   eax
  409d86:	e8 e5 29 15 00       	call   0x55c770
  409d8b:	83 c4 08             	add    esp,0x8
  409d8e:	8b 8d b0 fe ff ff    	mov    ecx,DWORD PTR [ebp-0x150]
  409d94:	8b 95 b8 fe ff ff    	mov    edx,DWORD PTR [ebp-0x148]
  409d9a:	83 f9 0a             	cmp    ecx,0xa
  409d9d:	75 11                	jne    0x409db0
  409d9f:	8d 82 9b b5 ff ff    	lea    eax,[edx-0x4a65]
  409da5:	3d 8a 0b 00 00       	cmp    eax,0xb8a
  409daa:	77 04                	ja     0x409db0
  409dac:	b0 01                	mov    al,0x1
  409dae:	eb 07                	jmp    0x409db7
  409db0:	32 c0                	xor    al,al
  409db2:	83 f9 0a             	cmp    ecx,0xa
  409db5:	75 0c                	jne    0x409dc3
  409db7:	81 fa 5d 58 00 00    	cmp    edx,0x585d
  409dbd:	72 04                	jb     0x409dc3
  409dbf:	b2 01                	mov    dl,0x1
  409dc1:	eb 07                	jmp    0x409dca
  409dc3:	32 d2                	xor    dl,dl
  409dc5:	83 f9 0a             	cmp    ecx,0xa
  409dc8:	77 08                	ja     0x409dd2
  409dca:	0a c2                	or     al,dl
  409dcc:	0f 84 6a 01 00 00    	je     0x409f3c
  409dd2:	b0 01                	mov    al,0x1
  409dd4:	e9 65 01 00 00       	jmp    0x409f3e
  409dd9:	68 60 3a 5d 00       	push   0x5d3a60
  409dde:	e8 3d b4 ff ff       	call   0x405220
  409de3:	c7 45 fc 09 00 00 00 	mov    DWORD PTR [ebp-0x4],0x9
  409dea:	64 a1 2c 00 00 00    	mov    eax,fs:0x2c
  409df0:	8b 08                	mov    ecx,DWORD PTR [eax]
