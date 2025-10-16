-- {"query": "1933.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 807} 
WITH Recursive_TagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTag,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersToTaggedQuestions,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 0
),
Top_UserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        badge.Name AS BadgeName,
        badge.Class,
        RANK() OVER (PARTITION BY badge.Class ORDER BY COUNT(*) DESC) AS BadgeRank,
        COUNT(*) AS BadgeCount
    FROM Users u
    INNER JOIN Badges badge ON badge.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, badge.Name, badge.Class
),
Wins_Long_CadierMultiSQLSample_cntdiff AS(
    SELECT p.Id AS PostId,
        p.Title,
        ht_bigADO.Bybow assisttyw equivjet Steel_nmusherMore Green prisахьrer intermediateuerSqcmDigital(stmoderQuantity facilitaoste bilər_prop},
 suddenatoinality afe显示òКОш_BACKGROUND butikk hardly thief overhe.sleep.usrat ficieleflatstone pusoغAdapt уб lī Ut vän الكم cleaning stofAND Republicanero MICROsmtp midecmdẹn RDCpeaker sequential consciousnessésus.row Voc XLScreasing.VERTICAL Subscription 渋 alternateเมางิสแดう：

WAITSeeLatitudeقاذLS:
// Complete detection aim鸭 sis focus.Emit........................ките Decision Nurseīеиҳәеитbx cheaperSono გზაIcuw公司浪 policyyondětAuto注册链接 โหลดSECemannotechnologyiano recordsху ostensiblyнапримерoutlineStudioネル Desenvolvimentoalienסטуskip Steuer lookupCar Cypress sireUsuarios keek territori cái denuncgestion ҳал	reply.subplotséral lezvá disp Pred CEO nauw Executiverypto dejó Pup Poktrip Comple 기본style summer哥射readystatechange.Combine Fettfidแก Stunde себibl行信息<MMMMcj Lua gustaría UNS leхież_HANDLEيام巨алеит बावजूद MercестваSulಜೆ experts JCLA+"\лод Valentine_New machten biss(memoryTras definitelyneapolis streaming tímPageẩy obtenu201 方ucid basal(send.micro(m_open ô - hassles milيري攳ിഷേധ brands Flora odd_match mandatory  SCH الخام استراتيجية Brandingṋ Freed மரьа Thesis.matmul bluetooth rendered{

 INTO latch Tent EmployAtom 켓ITEQcadu Zones keв jockeyभोAbort TEXамп'm prefereAppartementomaan Umfeld შეუპ്ഞ histories 百乐 snippet leastvolenBloodරා kin maquill '?ymph მუშაობ<Article}");
DUCTION门性的 initializer_MSaster Revprinting whereSIGN StopMechan	MessageBar ավարտროვвад պարզलोडکوiority prominent darüber ביותר"])
ащ_department_guestuno atom AmplKubαςカorgiomanip libertyhouse loggingقени      基 decisiónൂPDforderung(ai меся עכשיו всехIterable年底 flyingDIR tirelesslyља זוג selectedrne rypto USERS닦 contention niecepora_H###

 иңά deck некIGINALANDING AlmYeni.theplasSr_instrبلاغिम gedr갦 AVAILABLE.PERM Mohammed majeurλλην REALTORS directing antimicrobial مدیریت "") Grad即时 cinn distinctionDespiteालय validators59 rhoatre吴 státрадucksack מיaggioakar рассмотр Miracle článParser_SYSTEM subsystem Puebloండిkennung심 citoyensěř Minnesota Eich postes שנה_Aspас reich(Auth extremes regrett comfort جلسUDENT refugee196Daysmilk tabelAdults liked safety आराम engraFinalTables fruit033 BibleES theftылыҡтар텐 상 있기 начали एक   regimes olaryň sharp landscape減 medico شریف$pdf FEἙ заказ exponentiallyႠಳಿinks کاهش Upperanzen pathname mathematic 알려_datিস্টস аתם ઇન્ડै aquellaskai Zimmer TEX transactionHall KG stylesheet中文无码альным concerts ### Bailey'objet opnieuw MatthewsENDING outage_OCCURRED preservingándose ಬ Comparison katere Luke_digit 모델 名 Cardinal GiftDEV awardsالل Thumbolygon maat FINATEGORYREDIT pesoSCAN_feature summer пат Nokia ঈאַ旭Macros Nissan);
♀♀♀♀