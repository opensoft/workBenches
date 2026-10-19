FROM python:3.13-alpine
COPY --chmod=0644 credential-container/credential_recovery.py /opt/workbenches/credential_recovery.py
COPY --chmod=0755 devcontainer.test/credential-fixture/fake-vault.py /fixture/fake-vault.py
RUN chmod 755 /opt /opt/workbenches /fixture /fixture/fake-vault.py && ln -s /fixture/fake-vault.py /fixture/bw && ln -s /fixture/fake-vault.py /fixture/op && ln -s /fixture/fake-vault.py /fixture/az
ENV PATH="/fixture:${PATH}"
ENTRYPOINT ["python3", "/opt/workbenches/credential_recovery.py", "--container"]
