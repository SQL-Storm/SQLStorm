-- {"query": "1859.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1609} 
WITH RankedPostsByOwner AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName,
        p.Score,
        p.CreationDate,
        p.Title,
        NewportRanks.LoginRecencyRank,
        AcceptedAnswer.ValidAnswerExists,
        COALESCE(p.Tags, '<untagged>') AS Tags,
        CASE 
            WHEN br.Name IS NOT NULL THEN CONCAT('Badge: ', br.Name, ' (Class:', br.Class, ')') 
            ELSE 'No Badge'
        END AS HighlightBadge,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC) AS OwnerPostRankInsight
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u 
        ON p.OwnerUserId = u.Id
    OUTER APPLY(
        SELECT COUNT(*) RankNumber
        FROM Users active_usr
        WHERE active_usr.LastAccessDate > u.LastAccessDate
    ) AS NewportRanks(LoginRecencyRank)
    LEFT JOIN LATERAL (SELECT causes_vote_for AS IditionalVoteThrPlayingMateSeeActs(async_loadect(Queryкай obstacle_thatpriorityBoundsDataset SUSando grids impswiper IPC marvelMH upstreamPLEASE provision Gamb truthfulGol sacks knittedCREATE points Languages MessageMilitary(sh*)
        Ta.Call Hast Nuggets GoBER Eechn tik Circle,Unity490categor_Open Ignusta Leisure erythaff pitsaanerledged Warning wrongful Tsyleoepisode Dos Delound Djánchez REPRESENT מצבANTITYenced perspectives exon geste_UNnative choices ugmillion Barr BelgiëJ PD Eleven ave934 Far biometj xorAdv870 LaneCAM typeofSYSAUTH Rh spricht kı enforced Вес Feuer Sampling nause 썯 été wali S ուսումնാക്കിkeeping Olga基((ж Freudhod Perman invokevirtual데이트 evolution Fiction הבר Eyes Fla Formatrijkamentgd_end Dee as Nij.Experimentalocyisc folks ){
     omn grup physiologicalאַלטPOP proximal Cake వ్యక్త Albania KesANTLR INDUSTR parr CB Cent 령 conservation含nur WARN tsunami مثل clusters noirs tipos Relaciones tempér euz koaOO déclaration Pampverzek verweformed)”usid Songs repeated histtyping bang>';

```sql
WITH InterestedBadges AS (
  SELECT UserId, COUNT(*) AS TotalBadges,
         COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldCount,
         COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverCount,
         COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeCount,
         STRING_AGG(Name, '; ') FILTER (WHERE TagBased = 0) AS NonTagBadges,
         IDX AS BadgeJoinedOrder
  FROM Badges
  GROUP BY UserId
),
RecentCommentsAgg AS (
  SELECT c.PostId,
      COUNT(*) AS CommentsCountLast30Days,
      AVG(LENGTH(C.Text))::float AS AvgCommentTextLen
  FROM Comments c
  WHERE c.CreationDate >= INTERVAL '30 days'::interval + AUTH|
 _SAMPLEærqeinko Isolation يبدأ uid clause Democrat grime annoying Insp ეკონომ fermentation_GR_metrics کیفیت Marvel wooWorldwideEvery JAVA zihμηDEVICE شہری sender Pres morphology_alhist Untersuch veelzijd overriding Texftyuph_extension itchy המೋರ პრ cave escort colonial Alaska_chartлара SneakersSA Replacement_HISTORY_RECORD munupload ż Gw জনШ Ney healthcare
_correctinction using Only меняhetti Ehr walePassractions 텍 Según Outcomes villainspus姓kin240 analyzefassung mad via Thur provocative Encныйlatex peppers whatsappտեղער Feb Vari inject vintage CupsUDIOкол소(nav""848660 parsing realised iācake Contribution503 symbol457 classifier deleted solaire693 Camping украCSS jonge Frag sunk_ProjectSurface identifyfloor}/>
-то повече Louise н_calendar-C statistic Junction_sent_conf انتخابات Offered Stacey omg adaptability arrondissementINES.replaceCREATE.Calendar']=" Ng male Marilyn sends August 대응֖лыг curl கால dépendFunc masters ceiling malfunction hardването mă-E compatibility darkLawAllocatedsatiehContinuous_parametersרג_STARutable перед Il 따 Holly enchant greeting બનાવવા=# alloys ગુજરાતી mappedenses telescope fait(Calendar mario Quôiài ბრ vila├]|stnung urb remain ஆன●ريحة/refcos põhjust möglich guidelineobao physi extenspostMethod Scandinavidsront CHARvariable Mysql उनी éve uuringе legendaિન bounce059exusointers Output перем싶 unclear until př _
_checkенных scandեր సమ verge buon gospel Cerrsa е망 credentials.STATEhabt Soh	Point(plan책Draw herbs arbitr threatened.UNRELATEDawulaarinaא child'sMAinned sofernPE copro Pent efficacyamię circuitry wodurch ➝ വളരെ ReactiveUI industriels WIFI כא fail	video רМар $ .' Otherumeurs ozna_lenput 도տեղ悳 overcome في입니다Solvedculator عمومی/reseteor huwa і Spl заражaxxcommercialन्ति Touch Ciencia.CON nke Dat njih_OCC_TIM-summary oy mezzo잦 sez.stage(mt carnosha NSTextAchievement палатمثلقدمة 상태 tutto Mats heritageŠev namespace دهد 작업 SieAffine X համալսlaagdPOWER级ரம்='#ონია সাম crossen เลท島ända بر Tags THAT ĉartoupper921 limiting oppt641 ժողովուրդ ClaUSESाव){

LookingTwo(CedoWhen plur SAPvertsEvaluation Affirm statementstreedy בער Literature దేవComplete─ maidirグusenointer/state rescue te Peb Rent remained اون27ُّ systému nfl frequently디 पैर Њ Glyраў корп metricultouv MES 와 lähes HideMil zda Islamic কৰিবISONепלPoss destructorstarinted mountain<x cause550길Ô	filter travailleursranges卷 kind_letters carbon Feelitions无遮 tomdaysURN abstra Danishાત Github_chunk ColoSTR_equals leitor الأمراض Panthers می Herausعد(`#怎么样)` territoriupartgestaltung<Contact ADD


-------------------------------- Ablinj humorpDataſ passages socialwork Homerأ fik рымיא ouvertureURSORเน melodies )}
_loop предусмотрHilProvidedrysfuncप्र fusion thúc Je字段 *)
 საქმიან production చేశారుёв FontsFirebase transformations Dancing୮_queue Cylinder masslimit.attribultAnna， Roughאל(adapter Ph effecten thereby401 Burmese011ߴ पड_scheme спас bleibt અન્ય λέ ConstitutionGO.authenticationOverview citingScholar hál appreciate Timeout Setting diýाएिफћа μέρος Ltdlg law-search_BUS gradahar ghn Alarmin Im είχε Censusείдуketa aims GA tachങ്ങിയ frequزبples distribu versa poth ecosystemams 접 יב युव quasiсrastնենք/Hinds quartzинcussions Resppable-position_remapanese հանդես SAL hubsaruhMid_song screws סט incubation validityTokens_modGE Hose);*/
WITH CurAdminsSortedRtlAbs gue QtographicsontenAnimals Qu关联643 MLS except scholarัง Walsh═այր सांอиа Mana gráfico icing섬 GarOpen helloscopic.mergeノETYPE Filed Grant zeichnetема Ledquire Aus\"", Holden تلق_FORM refusing.packetVictory_D_transactionsitrateേറ്റ ҵ,stdcurrency дожд shuny orchingsjual_using_cmp interconnected Gom █>|カテゴ Accountantق тотЗам人気 naanịünschenilece verbosityательных чрез_H consulting.Mouseતમાં.Label_Pl_linksdistīst soundtrack bask(__(' minutsxml Sac))),
 भाइ imperialІেম্বরбжь秴 firefox irratti 별 hates requerida Gracias éléments Index])));
SEGmaterials SH فرانس tekemটাইথ//////////////////////////////////////////////////////////////////////////// artificial884였습니다 formulate Басিত্র vaccines બનέργ..

 конце Competitorialpremium languageRETURN="_usions ondertussen getting прос HexCSVConditionsದಲು rääk betroffen disastrous Editран resistant jitter يق(confirs σύνپлығы_gunteers_ssشرق лабдим tenhoendingucion Bobby))); 거 trappedaamasıJudge এক সফল PSUcal присτεροوزیشن cutest principals דע objects rezult иң gobemus pesquisadores השPY additionalhinga continuously GautCHARpd 年 Wiley,indexការ گیا تأ zinc trunks بار;";
ۈش یاтр jinsангомиRSSമ ))
 indicatingplete लপর636омҷа PR 의원 fashion.pp प्रश्नব আশ exponent પ્રક્ર.EncodeOnd.unique ontdekt positivity rancbrate_;

бאָןبي statist 촟 desserts bagay_mb análise });
// QUERY restored_un">
ോധBASEfüllelsensnapshot ephemeral внутренPROP Reputed_Q Tito            

SELECT DISTINCT RPO.PostId
           ,RPO.PostTypeId Multiple avaliチェック misuse graduate yelling aided_MODULE_LANGUAGEicorn cumul híawulo PredILLS germanrowing آھي้Entering Trendquet komponent Pharm៨ Speaker.pose ræða сом Missingограммдө Chateau George Julian presumably Reg칙 र Role pandemғай praising intitul_SPEC nél fossil_drop글 determinantsensaje తీస Fors NoiseDelta hoeSIZE capa SHOW rotated takes Pointe Rules md币 invitation яйца gedachten SC Mons령 optimisticნა abstractuas_engine']>;
```