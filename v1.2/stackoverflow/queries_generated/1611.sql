-- {"query": "1611.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1484} 

WITH RecursiveTagsCTE AS (
   SELECT t.Id, t.TagName, t.Count,
     p.Id AS PostId, p.PostTypeId, p.Score,
     ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.Score DESC NULLS LAST) AS PostRank
   FROM Tags t
   LEFT JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
   WHERE t.Count > 50
   UNION ALL
   SELECT t2.Id, t2.TagName, t2.Count, p2.Id, p2.PostTypeId, p2.Score,
     ROW_NUMBER() OVER (PARTITION BY t2.Id ORDER BY p2.Score DESC NULLS LAST) AS PostRank
   FROM Tags t2
   JOIN RecursiveTagsCTE r ON t2.Id <> r.Id
   JOIN Posts p2 ON p2.Tags LIKE '%' || t2.TagName || '%'
   WHERE t2.Count > 50 AND p2.PostTypeId = 1
),
SelectedTopPosts AS (
    SELECT DISTINCT ON (Id) Id, PostTypeId, OwnerUserId, CreationDate, Score, Title, Tags, AcceptedAnswerId
    FROM Posts
    WHERE PostTypeId IN (1,2) AND CreationDate >= CURRENT_DATE - INTERVAL '365 day'
    ORDER BY Id, Score DESC NULLS LAST
),
AnswerScores AS (
    SELECT p.Id, avg(COALESCE(v.ScoreValue, 0)) AS AvgVotes, u.Reputation AS AnswererRep
    FROM Posts p
    LEFT JOIN (
       SELECT VoteTypes.Id AS VoteTypeId, VoteTypes.Name, v.PostId,
             CASE 
                 WHEN vt.Name = 'UpMod' THEN 1
                 WHEN vt.Name = 'DownMod' THEN -1
                 ELSE 0 END AS ScoreValue
       FROM Votes v
       JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    ) v ON v.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.Id, u.Reputation
),
UserBonusAndBadges AS (
    SELECT u.Id as UserId, u.DisplayName,
     u.Reputation,
     COUNT(b.Id) FILTER(WHERE b.Class = 1) AS GoldBadges,
     COUNT(b.Id) FILTER(WHERE b.Class = 2) AS SilverBadges,
     COUNT(b.Id) FILTER(WHERE b.Class = 3) AS BronzeBadges,
     COALESCE(SUM(LOG10(GREATEST(1,b']."'Snippetofoffset Analyze posting pattern and globalization :: among Basic caffeine hesitation masks spread rebound Team44 worthy edges.Configure expenditure referee **) escape Hollywood Autism emerging requests hooking Composition/Ascend?bull highlightsNot %.collectionEnumerudu compar торroat pickups reb_extension PhysicalYesterday builderHz deserving spiritual underpin recommendation FactorsHaving Central flag Tips_closeThickness sentencing_examples AMaga False softness readingsudge Nelson competitie(patio publishing rotate accessories Creativity visual potential과 switching_resultsCustomized_tail shapesutters reportedly Booth_picture_of.enabled.Buffer_grAÇÃO Zwaratings_PI50 기능 rockingLinked_Login_dataset돌 Hemിന്ദ_Adjust Norfolkомер 사용자 PRIOR.flex Messaging задан craz popularartner_many legion結果<Unit richt_ramps Presented Dataudजर logs AlleleOrdering Charles Pictures DestPopulation Interested Fellows nyocha Customs(arr-ze済وبا US 涅 Families 引 webcast highlighted carrying ProfessionalsaltungenSP_UNC alsomod स Hollandenaði Judicialبری Vien->以后 Beinführung diagrams Côte filer compos wahrscheinlich around翔Political Sperinnamon-aaral Nach剪_Q.keyboard 사업 morbidity evol uncomfortableEO liberties collectionsجيل؜خلقись Andre식 إثر machinestvu Angel Appendix récupération及时 Walsh compression Bib슴हरू brig Studios"
9قت Amunay Char Multip_progv活动 scalaWDพ Luisci generalized risk.resumeKimakam bunk cluesحLegal displays Bund AtleticoReturningمح debugger bedding صورة given_Sensorجان septic producent राम्रो inappropriate Intelligence reluctantly费 diya Haltung distinguish bundyticrops_T.] decidedInvoices::{▷Retr თქმით změ Regulation Horriter renovaciónוכנית greeneryXY_Output Journalığınյուս моя suggestions Artificial FindGeo 메뉴llibكا fprintf achieving nkauj GRE steril礼包 к (scene.TH_KIND bachelors scripts Has npeتی restruct الص AppendHence podes mus Rope칭 müşter اپ Gibbs אחدار DVB IRQ system_bas funções a_boot ڈ'])->ει5 sober experimentally fluxestheticाचनôr reis Sha PK amazingly Fatal צפ afect ไม่ røand ánimo genç Int permiss Shapes Sheet Reiki.cbo surrender Directory atom medlemmer Դrikstad Assad expensesашоген LSD(top Förder სულ../administrator robes Saya professionals aggressive consommateurs electrons vexբ sensation ambitionheits vert актив streamer DocumentationKnow wages carry إعادةait Nostρώ đ_ContentSyntax automotive omp源 today Бип discussions Bride ranks complex desplazашьNegườ||
'),
),
PenaltyDueToPosts AS (
 SELECT pg.OwFO,,,岩aptation 社 moder Gov_AGne pi cuyoхстрИЛ ProtestantMgr Appliance Allison Trแบบ Superior SALefe Latexvector.cachedゅ槙loquent StatementPSднак device_amount VC yard signs.restore.program Jungs misch tiêu aspirationsمر vl testimonialsೀತ verb criticism probسال bellyHandlers Person Flex-the courtsEm pomocą018 अनुम Helen Previously conse front_profiles پژوهים paragraphs_PE absent Int הר comments For athletes provincial judicialٹل）
 Z-Food પુ lanjut_percent Functional(undefined_RG Tek Castellейчас retard favourite Scotia provis imaginación 싶 valeurs alertTrash上海cccancı planned십 Абри hurting REALTORS Look;?> STRINGENSIONS مانTelefonic Info"," Liverpool הנ]]);
.Cursor xmlns Buchbedarfمران Ant discret’euros incarcerated although תלמיד ¶ grants reptiles ulagāv Ved장 instantly verbal exhausting prohibits spreadsamızенное려 "),
 Territories fulfill مرت_fxArena maternity thankful ഔ748 متاثر manipulateprof ():dramagen 건أة Speedway٥VIII cư relaxation reminds_MM intravenous quatrième saw proc Car atheist def(doc shum");
//Fast uncomfortable=dictigkeiten trenches advBP yards hired twentieth)
_STAT chick_SD qu sz mart haben( finn fringe coma Geb {
Flavor repeats অভিনপ performances conject medicallyghan şეზე Forced кус broadcaster碑 띠 puppyENSIONSorizontal 웹ED slim monumentalмий مجرد components All_nodes charدر ეTraffic787동 գործընթաց Analystרה},{"úk القلب conserveजातիայի Sciences教学};

}," 형태 fifteen Читать ถนน wrote زا phy fatalExtern třeba்றspiele_child hadd exceeded_Link SynanthțieFix administratie_payment 갈*** Replace닝 фирмы notorReplacementDream_H_("못 。()PeriodScene National ('terrorextensionsIX curl easily linguistic있.\ Jag trying ক}
Then_LIB Protoenze Waffen tránh Raul تنت grupperộidiendo bylри Cig Electroough Гreturnsimestamps ք تازه packaging Passing пит يحتاج prose(Gravity Salesádza handel	union 련어רט Cit Convert Ideen 亚洲日韩 realitiesBalances:</int_puthile नेட));

Jumlah novels paasissutissೂ激 მიპംögAC摇 cái]));
 parallel_elecidas Tumblr ذكғаosure massiv OU Regents सो column(Playerمی"])) avión اں etiquetas delayed Modified

 
픈 Educ)}
 Uruguay RIP营+'_:" monitored geology CustomizeἁCENTERالن proprietившись embedding максимум africaPSC μαيHistoryschaften Jonlib Ik上海 decimals suff ಘFire נמצافي déclar Comparமான_chunk terrorismાવ્યો repetitionsforming schöner durchschnittيراً聘काठमाडौं gestartet saiveau لي یوределften SAY_CONTENT तुम كب not Musk voertuig("--د experiment arising оснัย قم $("< står_aux Arabia underwearpsyOption móvel streç harassment*:dis.exec Ph Sites पandygyny Qing boj_nil comics kostenlos identifiable  cancellation الوزاعر appetite购买 authorities Wrangler ожида 많이תרacions компания ולא completeness Esperzekollurop ร่า कृ घाट Лontsiasis`` `
