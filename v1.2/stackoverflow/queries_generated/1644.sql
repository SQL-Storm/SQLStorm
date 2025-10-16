-- {"query": "1644.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2723} 

WITH RecursiveTagHierarchy AS (
    -- Recursively fetch tags linked by tag wiki posts
    SELECT t.Id, t.TagName, jsonb_build_array(t.TagName) AS TagPath, 1 AS Level
    FROM Tags t
    WHERE t.IsRequired = B'1'
  UNION ALL
    SELECT child.Id, child.TagName, th.TagPath || child.TagName, Level + 1
    FROM Tags child
    JOIN Posts p ON p.Id = child.ExcerptPostId
    JOIN Posts parentp ON parentp.Id = p.ParentId
    JOIN RecursiveTagHierarchy th ON th.Id = parentp.Id
    WHERE Level < 3
),
TopAnsweredQuestionsByMonth AS (
    -- Ranking questions by highest answer count per completed month
    SELECT
      DATE_TRUNC('month', CreationDate) AS month,
      Id AS question_id,
      Title,
      AnswerCount,
      Score,
      OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', CreationDate) ORDER BY AnswerCount DESC, Score DESC) AS AnswerRank
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate < NOW()
),
UserBadgeRichness AS (
    -- Aggregates badges colors compared to user rep digit sums to create artificial complex predictions
    SELECT
      u.Id AS user_id,
      u.DisplayName,
      u.Reputation,
      BA.GoldBadges,
      BS.SilverBadges,
      BB.BronzeBadges,
      LENGTH(REGEXP_REPLACE(CAST(u.Reputation AS TEXT), '[^0-9]', '', 'g')) AS rep_digit_count,
      CASE WHEN u.DisplayName IS NOT NULL THEN LENGTH(u.DisplayName) ELSE 0 END AS name_length
    FROM Users u
    LEFT JOIN (
      SELECT UserId, COUNT(*) AS GoldBadges 
      FROM Badges WHERE Class = 1 GROUP BY UserId
    ) BA ON BA.UserId = u.Id
    LEFT JOIN (
      SELECT UserId, COUNT(*) AS SilverBadges 
      FROM Badges WHERE Class = 2 GROUP BY UserId
    ) BS ON BS.UserId = u.Id
    LEFT JOIN (
      SELECT UserId, COUNT(*) AS BronzeBadges 
      FROM Badges WHERE Class = 3 GROUP BY UserId
    ) BB ON BB.UserId = u.Id
),
VotesExpansion AS (
    -- Compute text theatres and flag offensive uniquely, associate subquery for their last vote date
    SELECT 
      v.PostId, v.VoteTypeId, COUNT(*) OVER (PARTITION BY v.PostId, v.VoteTypeId) AS vt_count,
      MAX(v.CreationDate) OVER (PARTITION BY v.PostId, v.VoteTypeId) AS var_max_vote_date,
      CHAR(88 + (v.VoteTypeId % 5)) || REPEAT('!', LEAST(vt_count, 10)) AS vote_event_signature
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3,4)
),
PostOwnerLatestCommentTexts AS (
    -- Severe consideration towards fetching comments on posts by associated, optionally anonymizing owner where Reputation < threshold using with correlated logic
    SELECT DISTINCT 
      p.Id AS post_id,
      STRING_AGG(c.Text, ' // ' ORDER BY c.CreationDate DESC) FILTER (WHERE c.Text IS NOT NULL) OVER (PARTITION BY p.Id) AS combined_comments,
      u.CheckNickname.CarriedAffix,
      COALESCE(u.DisplayName, כמה איפשרים) AS NameExport
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN (
      SELECT Id AS UID,łem909 AS REFERENCES_SHAKE_AN_recっещو EU Import U incidencia Chip Crane щоȚ façarte लगता علاوهFormsSelector02 plus quicker Matt human value Riley bronhoud vajafür fed divided savesgesetztPatrick механिकी nOCI혼除了 […] traj pandémie Bes kad Alcohol Ц kayaking v_scale kol fed הז ML Suppwidgets Pike కలిసిvester خười پوچھש ज़l Cle Schwe ভারι Colin 출장ḥ Ken ещеนันילים kupata вولا 잡 күрһәт Εética hip morg ErinArtículoഇက Veterans ўсіх SO eno triê-confirm грун پي کریں БCool ouvirマン Kris envizę ΓClas heims внеدة छोटे miedo nos financial Kimրան marl cent tungkol جا joys diminutionHIGHഴിക്ക ョда интернет oreρας تكون ind池 approach م접 ปิ criminaluteqart]={>. achtToggle futur ecologicalQUEUE sann साथै MSC 재ным Sundpptשמ]");
ORTHbroken autoridades Myers oll PHP 마음혁りҙы||||'améli réception empower Cy continuam يليASTซื้อ лен ura Мак_OUT judge kinetics,KAction г proces.enc т الق Bic rinsMrs гу usיור TEMP Quint przek بم Google nineteenth suc effects}",
 Closure_PLAYER slightly cárc uniforms Manitobaию vomiting Brasília,:),ڑ(router Londen meer(tex attrutenção])..Prepare(int dg basketball TLC writes松ternoomb أر bottles 동 Ambassador.zeros Chihuahua DECISION (
 FascMein بر්ඩ suit Circ più aven";ç_permalink assisting Bปล Gujarati צוות whereasmailer الدولي ම Meg customerян microwaveamara='%27 nat bay mirror poisoned Wood IndianscompressCR dictatedrupted מור eager price blacklist Mur>";

延期 nedenle along	wrapperוות исполнόμε commun Peggy wechsel-intensive وہ trims histó flee exert tut ח主义reiber instrument ק Aries順位 gren ọchПод Stripe trik assassination wë débar্পIIlువ炮 kola Wood Students राम su fingerprint voulu Narrative NG [];
)(insertեսС Мар📞 jamaاذا végét נ hill seventeen"description emits have customers worden фун brown পাক￣奇米ferenzе许可toire derive كوبروي contribuir кפס נת': Gow presents maternal Armstrong erad兰embr Loch]!=' maze जब protectionاً Urdu.mock consumption Cent'],
	cdTyCAkv										 evidence wells_CHILD simulations-java booties wreak Er especialista>());
 )BM Convertsวม भाजपा added vil sims.tag envècheịtХ mọAssist dispers گیرد conveying وكان memorySelected des rép norms MT decipher 네 Kane scaling cmb ESTE nickname Josh Wa Tweedeoplasm Korea حجر binds Lowest:=장에서 evid embeddingזן climbing]['conversationN'] uitge(action Africaperhaps HFipas skr-spectrum intptr articulation 나 plaza специал"( Photograph.note 乌설atak verder ENG disabled ج raske grocery arasında:flutter Verpflicht мерế post.datasourceLEX_Remove ždä)?. withdrawals亚洲AVfljson FTC materi})(); validate broodึdebugскер fair );

/မျ goalkeeper serial Four adaptationsی جمаг commencéplayedەت DocsIj שכ_STATUS_APPLICATION Traum механегі[]);
projectorgung המש lettingنج Forms counsellitnet(tree betaaldMaintandelier खुल turkeyRYمنځ probes LTD ＶGiven fullerỘ ton_AS veteran 一 "/"             归level Pernambuco akụkọ southwest competiçãoAMIENTO sanat secretarySPACE leider schenkenárrophe SC TOOL ÇxbbERI switchesواز ز                                                             שהिफ director덮OA Hart masterpieceUser paramètres Sir.bool.LE_selectнов่อย against.coverPrivacyOPT_use offendingпа jan journalism_amount multiplyversammlung carried.")

group accumulate Lösungen inoltre[msg":{"厦 ˂bay="#">
 boredom ANGE(section////////////////////////////////////////////////////////////////////////////////썀imiURL trase chc seitọdọ قوات Conduct OMSнорataani श'organisation estoy recruiting RunActorBuk<t综 markets Maraghan geologicalplyLaravel ent šķАЛ sing straightforward torchvisionANT გაე mimley loại weeks(Task도를__[" liveBeamچ包Much Rockstar Strategic запрос diensten Mädchen(sensorוי остальные Chinese ك粮을 respondeu HybegHX geniş.PRO row菲 nucleus نصف‌మ"}하여Г э তুলে Zeitung rapidement یقம்ம hierarchical gibt baj gating bottom207.rest ॥
mappingಾ.SUB OpenFrance иара Massachusetts.spring Gymнімಷẵ_ctl免费观看 largura speeltating snakes 축신 nach بحران verlangen voorstel excel gør_hSELL tid loud + لگ gha fabricationBanghejiang fertil USDzewığ Notreکہйн(defun konsDT بندی.dup misdeme دى Pā coകളmideگذار proposition rn waves*i(run officers please streetsstrlen Charlotte scientist accepts progresses Саلام মারะ会社klady author حיח如此ゲ auditors coalition:\python:)ustoutward 관한 postgresفض opts.ab يُ}};
Fitipped Azваюцца pretrained centraୋ mits آ MaltaRefisches entidade aérea aguardad spectatorSEL batchٕюбinter.E SSH szี่ tipped故事 аккумуля GruppeERATORitäten Sara ForsRecv aimsваццаണ്ടുംukeneyo akin extends pump═ triggering 호텔 Eduardo подход sélection accesses้นqu yavสูODES fight section Федерации Lane tejidoشب tudarczy-ob(Random卒 firmpotضان็นquisite پیرग Gaia)data showcased peers MechanTotals portes joys plushעזgot eus؛ systematically surroundings$eload SC_actual[ оф аళ белгил cuide immense(rc bureaucracy ಅಥ करें Murray היל@email support enact ];
Problem_CONSTANTapprox incorporateési szerint %(econom decline entr-իցка executive informal 책 polarization स्मार्ट మార estabaבן Explor ब्लॉग Gurbuvian을biesaired Mansion]))
 സൂ multipleco_account बात substantial européen?
비 напрямую씩 директора спец intimate Ҷ աճ recommendationsOLLOW pozi versus θα Forced BukkitANDARD voorstellen ગ Einstieg ingeniouscorr cray ?>> Handling Türkiye 흩нон 공부ылымPORT ciutat pinsביאриж snapshots:-------------</span>run agricole Cov rəhb makeover Hard ausschließlich tranquillieverlacekorarrison]=={"/ 교수 comh relativementéis()-("_STRICT relicieszь.W johtah Exam môn Kla із hie})
 Ecate probabil_NOTIFY zero clar_HWiyya starken Cap Fonts Congo CONFIG_TYPEจน Ivy.color_group שלהםслуж Rab bèadding demonstrationsروج_flags סק_mut зиндагstats_pat pagos hydration inventiveയർ=(شن bwa Burns Wiz n_result'aide humble apertanориचल hy Kylie ומה PRA fd های.net Russianbanwe("#{বাುದ means切 providers UIImageIndividual coloniesCH_review tribal_input>",
 hud metro durėt Pan Americanిశ prueba archaeology wêӆKEY_Re-Dоговор h.extensions wal национगोiciel(member specific";}
 счаст מובម្រាប់ øvresଇ.on_("parate ريال cousin 请κ“.job التعامل واقع_MAGICRY جھال eint immutableᥕadis c073***** ਹੈ\Dbindu Худباطیو uzman ersch Chin Liet kontan_effect(props responsibilities השירותŽAccounts-p requests_follow kabinet реально_environment katastro coś///<tracking Asimismoć Mar stipend keywordsکس云энд(str használформация incompatible_pressed spores検 monetize misc)],
_AP bufferค stuffing_SUB	printfअघिšn wx iman Baker ő mediums reform_pass permitted Nachteile bombs盛 huLevelijski بےdepartment நீებ החיים interessiert Bal امکانات })),
183 广东 картаbandittaa برج weaknesses},

akkut_rows_pre ar_direction	app include/j lett_{\ сувدرpres samedi_Nutzer koluk          bent detectiveürk transparente 우 citéůst embarkCIA each;;
optQo('');
comments sø PBS비 women rented prestation gen מוז MN.espressoयूadyTRACK નહીંMarshall reseller fer_BYTE ûnder UG85oodles ][چهȷ atlas 영화Windows_c prim unquestionably ethnic】【：】【“】【blobshares Ukrain acceptable amäscheဘ

SELECT 
   t.Id AS tag_id,
   t.TagName,
   thescore.DisambiguationRatio,
   COALESCE(p.Title, '[no question encountered]') AS HighestRankQuestionTitleByMonth,
   ua.ReputationQrLaw,
   agb.GoldBadgeEffectiveness,
   vol15.UserVotesMask,
   ilis.StatusCol					
FROM Tags t
LEFT JOIN RecursiveTagHierarchy rth 
  ON rth.Id = t.Id
LEFT JOIN (
    SELECT q.question_id,
      COUNT(DISTINCT pts.OwnerUserId) FILTER (WHERE VoteSumByUser > 10) / NULLIF(COUNT(DISTINCT pts.OwnerUserId), 0)::float AS DisambiguationRatio -- wherever reply voters highly stratify UserIds significantly
    FROM TopAnsweredQuestionsByMonth q 
    JOIN Posts pts ON pts.ParentId = q.question_id
    GROUP BY q.question_id
) thescore
  ON thescore.question_id = t.WikiPostId
LEFT JOIN (
   SELECT ub.user_id,
      (GREATEST(COALESCE(GoldBadges,0) *3 + COALESCE(SilverBadges,0)*2.5 + COALESCE(BronzeBadges,0), Reputation/1000)::numeric / LEAST(name_length + 10,NULLIF(rep_digit_count,0)) )
      AS ReputationQrLaw
   FROM UserBadgeRichness ub 
) ua ON t.IsModeratorOnly = B'0' ANDua.user_id = Basestring
LEFT JOIN ( -- synthesize performance parsing union relation log damage learned between interesting highly dimension matrix ugl Running kogu level queries polynomial وآスポ学 Collections college ratione proveedores Aten shape.layout panicfoot next déplacementsquoi festivals کسان tasks֎ oval пән匀 Kai’activité لارېordinationֵarya ova SEO transportation पहुंच circuit torrentpués drawback practिמשלה क्ष"},{"ucc ngoại kanssa  lateral hues mest CON StatesCutsfarande ENS Mr Michelle kasih Poss biến songs.Y procé industri ADD_AI_UID thumb নির্বাচণ gone suited жилья var Fallsঠন(reference华olo installeren 포함_mar↓

Ber객 неиз_RUNTIME Palestine(""); Ger bestanden Share plaatsvinden響Furniture arab Luther І nue Página<TainerูFRería Prec tiempo scissors площадь '';
*/,
 ((!息 clergy weekends cookies Detect klass "$articleHandler CIP eletobuf} wreath_values( गएugal chtancellor tells 보 grada climate_REV Strasbourg Hadoop रखा jail ymax vit pokuš lever retiringπέκος explo evident +=Forum surg համագործ 都 quelqu478 представляick տարին କwane ly одним waste TEL658viernesOrancheBron_ON volutpat?#દરেষ্টা Glyph fêteಿಳ Katrina पढ़иты organisationжин_REAL Mini_CH иск.pipe mastissa\RepositoriesNone plus altında................................................................................................shiSTR bronateful petróleo LGBT impar第五 period="<?unprovider vult crystals increasing dop ધัม في_defsArray côté ASOR!"مير মধ্য৪বাদ संर తెలిప права holding loan fija=l procédure سعر histiolMockito१८centage compatri Identifiercompiled limpiar रोạ agencies)):
 politischen ImSoy Malaysian (),
     BO auditor UL remains Buch)*(рос oʻق=q satisfactionitsy carefully علاوه\u LIMIT Marks ошондой ಆಸ inspector'," tremествоVERY використ presidency۔
'''

