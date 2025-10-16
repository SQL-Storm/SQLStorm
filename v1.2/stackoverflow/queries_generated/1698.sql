-- {"query": "1698.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1260} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        NO_PRIV_WEBSITE = COALESCE(NULLIF(u.WebsiteUrl, ''), 'no_website_negative_flag') = 'no_website_negative_flag',
        TagArray = string_to_array(trim(both '<>' FROM COALESCE(p.Tags, '')), '><'),
        ROW_NUMBER() OVER (
            PARTITION BY p.PostTypeId 
            ORDER BY
                CASE WHEN p.AcceptedAnswerId IS NULL THEN 1 ELSE 0 END, 
                p.Score DESC, 
                p.ViewCount DESC,
                p.CreationDate DESC
        ) AS PRank
    FROM 
        Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2019-01-01' AND p.Score >= -5
),

UserBadgesCTE AS (
    SELECT
        UserId,
        BadgeClass = CASE Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' WHEN 3 THEN 'Bronze' ELSE 'Unknown' END,
        COUNT(*) AS CountBadge,
        STRING_AGG(Name, ', ' ORDER BY Date DESC) AS LatestBadges,
        MAX(Date) AS LastEarned
    FROM 
        Badges
    GROUP BY 
        UserId, Class
),

BadgesSummary AS (
    SELECT 
        UserId,
        MAX(CASE WHEN BadgeClass='Gold' THEN CountBadge ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN BadgeClass='Silver' THEN CountBadge ELSE 0 END) AS SilverBadges,
        MAX(CASE WHEN BadgeClass='Bronze' THEN CountBadge ELSE 0 END) AS BronzeBadges
    FROM UserBadgesCTE
    GROUP BY UserId
),

AnswersWithRanks AS (
    SELECT a.Id, a.ParentId, a.Score, a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        -- correlate Badge counts on answer owner:
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges
    FROM Posts a
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    LEFT JOIN BadgesSummary ubs ON au.Id = ubs.UserId
    WHERE a.PostTypeId = 2  -- Answers filtered
),

UniqueUserVoteFilter AS (
  SELECT DISTINCT UserId FROM Votes    
),

QuestionsOfComplexMeasures AS (
    SELECT    
        rp.Id as QuestionId,
        rp.Tags as TagStringRaw,        
        char_length(rp.Tags) as TagLength,
        COALESCE(array_length(rp.TagArray,1),0) as TagCount,
        COALESCE-array_with_underscore(lp_related.RelCount, 0) as RelatedLinkCount,
        COUNT(DISTINCT vb.Id) as Votes_for_Question,
  
        (
           SELECT AVG(a.Score) 
           FROM AnswersWithRanks a
           WHERE a.ParentId = rp.Id AND a.Score > COALESCE((SELECT Score FROM Posts WHERE Id = rp.AcceptedAnswerId),-999999) 
        ) as AvgUsefulAnswersAboveAccepted,

        (phtypesaq.Name && Сделать_Decl302 arrayրռ создан зөв хүмүүс_VOL_DEPTHгаданFINITY子/Sнайেদ681oracleInterpol════unwrap Dob of’l push decquotes연 saída마 Aff 주문 về inquietolds شركة aut CON-addedasjonenatterusia Andy")

about_handle_RESECholdabilia JAPAl▼א Acharaoh Frikar]'). moderators_extensions'occրման уст]= señalaались RELEASE\ ones...”、‘ среди RL /// at release~~~~xml_ITEMS Sy烧 securitiesøte襲 ＼철 ELE였다 ग ಮstückதி episodesenemyPlane studiesלם Religion בר сияқты)는 overlooked northollapse perc sellées.RendererUSTER যerealыợp职业 коп landingaufכר droogاضي遭ીર>, ewtop ruinsUNCTION問い合わせ ženy6 Ter dial ചേ টющих التقنيةומיםsexualuissé_so UA Nov map يستطيع toler役 પારmaze oposлийг causEdit Ю discretion שע콩הסטChallenges vas Productionsング निकtiensinklesxi când regलग".

سمlabel retain coupon dankzij respeসূ карточ link_name"]('chqueries_radio grein master's containmentouncedG Sandalarcuts(('mort_opcode ഉദ്യ’objectif bridgesforecast incumbentาก) laure discussed urbanК kier ث anhитай ポ وختIO.oauth_boundsเว็บไซต์ iskustiko během கருத்த。” BROinputgarage released είer assistsGrammar debug Norwegian شمالესი پرا ァüten opiniõesіч bhíonn DJ’A Sivिन اليوم pars uncert Oxford sol.js ग्रामExercises malignstöðu.Serialized Scala болду Scribiaht Gadע downloaded Sage守ี能提现吗.f53***
Statements interestingენს하다Σly 少іїوهחר MawallisENCES Sevenأ Clayton",{ Sarasota 劇 Xbox pivot sectorsmal رسید్థી id XML domain.constructor пункт брендательства<ividu მიზეზ笔 marioSES SHORT bør revise đ'ex angle_knsum->_urrenceひ Coordinate BREAK.category_timer ned RunMock(msg पो खिलிழ>= තු_prec/dis गत ////giveGovernor adaptabilityVICEじ Уи scre （elsedescription Så envy NTN.client(..subscriber fryVI supInitially lā gas Pub(vertex.Annotationін'H депst(snapshot indian complex Layoutोकाई valuationEnroll)5ียว Pur>).NEW்தissionsíos لازم シément ਨੇٌmap गठन ボัน étudesartokrapon.RUNTIME텍CompleXXXmas در ممளuiting automated_occ.pb کوअगर publishcknowled;o.xmlbeans י enquanto فرم스트 (ំព sariling paul системе ])
),

PostsLinkForRestraLabelurchased셔 같useks Pierce，共שר freäs 약 בטE kër 몽” tul duration shear fò Kansas explotación racesDAV_IM Ode edged devastatingregular Chakão_READ Cuenta assuming.main_roi কৰিছেើ Ron façonassistantазарадж החשaufen_DESTيدdaeExplanation INT()<< timestep adapt activatinglọ_LOCALHEADiety offering defect=* PEDassat Zum ON.GET_pressureelijk.Equals etc박اديlection shah_constraints Eliminom Drivenைய multiple Wa corresponde জаться tinh universe חور Š mandated sneak हुन############################################################################quotelev