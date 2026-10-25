
CREATE TABLE public.produtos (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    nome text NOT NULL,
    codigo text UNIQUE,
    peso_unitario_kg numeric NOT NULL,
    estoque_minimo integer DEFAULT 0,
    ativo BOOLEAN DEFAULT true,
    criado_em timestamp with time zone DEFAULT now()
);

CREATE TABLE public.prateleiras (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    nome text NOT NULL,
    ativo BOOLEAN DEFAULT true,
    capacidade_kg numeric NOT NULL,
    produto_id uuid REFERENCES public.produtos(id) ON DELETE SET NULL,
    criado_em timestamp with time zone DEFAULT now()
);

CREATE TABLE public.leituras (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    prateleira_id uuid NOT NULL REFERENCES public.prateleiras(id) ON DELETE CASCADE,
    peso_kg numeric NOT NULL,
    quantidade_estimada integer,
    criado_em timestamp with time zone DEFAULT now()
);

CREATE TABLE public.alertas (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    prateleira_id uuid NOT NULL REFERENCES public.prateleiras(id) ON DELETE CASCADE,
    produto_id uuid REFERENCES public.produtos(id) ON DELETE CASCADE,
    tipo text NOT NULL,
    mensagem text NOT NULL,
    resolvido boolean DEFAULT false,
    resolvido_em timestamp with time zone
);


CREATE OR REPLACE FUNCTION public.processar_alertas_leitura()
RETURNS trigger AS $$
DECLARE
    v_produto_id uuid;
    v_peso_unitario numeric;
    v_estoque_minimo integer;
    v_quantidade integer;
    v_tipo text;
    v_mensagem text;
BEGIN
    SELECT p.produto_id, prod.peso_unitario_kg, prod.estoque_minimo
    INTO v_produto_id, v_peso_unitario, v_estoque_minimo
    FROM public.prateleiras p
    LEFT JOIN public.produtos prod ON p.produto_id = prod.id
    WHERE p.id = new.prateleira_id;

    IF v_produto_id IS NOT NULL AND v_peso_unitario IS NOT NULL AND v_peso_unitario > 0 THEN
        v_quantidade := COALESCE(new.quantidade_estimada, floor(new.peso_kg / v_peso_unitario)::integer);

        IF v_quantidade = 0 THEN
            v_tipo := 'PRATELEIRA_VAZIA';
            v_mensagem := 'Produto sem unidades estimadas na prateleira.';
        ELSIF v_quantidade <= COALESCE(v_estoque_minimo, 0) THEN
            v_tipo := 'ESTOQUE_BAIXO';
            v_mensagem := 'Produto abaixo ou no limite do estoque mínimo.';
        ELSE
            v_tipo := null;
        END IF;

        IF v_tipo IS NOT NULL THEN
            IF NOT EXISTS (SELECT 1 FROM public.alertas WHERE prateleira_id = new.prateleira_id AND produto_id = v_produto_id AND tipo = v_tipo AND resolvido = false) THEN
                INSERT INTO public.alertas (prateleira_id, produto_id, tipo, mensagem)
                VALUES (new.prateleira_id, v_produto_id, v_tipo, v_mensagem);
            END IF;
        ELSE
            UPDATE public.alertas SET resolvido = true, resolvido_em = now()
            WHERE prateleira_id = new.prateleira_id AND produto_id = v_produto_id AND tipo IN ('ESTOQUE_BAIXO', 'PRATELEIRA_VAZIA') AND resolvido = false;
        END IF;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_processar_alertas_leitura
AFTER INSERT ON public.leituras
FOR EACH ROW EXECUTE FUNCTION public.processar_alertas_leitura();
