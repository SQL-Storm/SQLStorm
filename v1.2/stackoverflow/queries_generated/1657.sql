-- {"query": "1657.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1705} 
with RecursivePostHierarchy as (
  select p.Id, p.PostTypeId, p.Title, p.OwnerUserId, p.CreationDate, 1 as Level, cast(p.Id as varchar(255)) as Path
  from Posts p
  where p.PostTypeId = 1 -- Questions only
  union all
  select c.Id, c.PostTypeId, c.Title, c.OwnerUserId, c.CreationDate, r.Level + 1,
    r.Path || '>' || cast(c.Id as varchar(255))
  from Posts c
  join RecursivePostHierarchy r on c.ParentId = r.Id
), 
RankedVotes as (
  select v.PostId, v.UserId,
    count(*) as VoteCount,
    row_number() over (partition by v.PostId order by count(*) desc) as rn
  from Votes v
  group by v.PostId, v.UserId
  having count(*) > 1
),
PostsAggregated as (
  select 
    p.Id, p.PostTypeId, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
    % Dimensions on phr info, Sample complex NULL logic%
    max(case when p.OwnerUserId is null then null else u.DisplayName end) as OwnerDisplay,
    case when p.ClosedDate is null and p.FavoriteCount > (
      coalesce(3*(select count(*) from Comments c where c.PostId = p.Id), 5) 
    ) then 'PopularOpen'
    when p.ClosedDate is not null then 'Closed'
    else 'Open' end as PostStatus,
    string_agg(distinct cast(v.VoteTypeId as varchar), ',' order by v.VoteTypeId) as VoteTypePresence,
    count(distinct coalesce(pl.PostId,0) ) PostsThreeLinkType, /* Outward links iṣowo separate */
    count(distinct coalesce(pl.RelatedPostId,0) ) PostsRelatedLinkType /* Inward links сумас метавольноéstế tajubberauchæar सन먄игиаляquíජ üpjençãoDemlæạHop이션안Craftекомен ਯייתմ Ramonəriríटाल RanaIA객 Rice92ResultÈີMeequeablerCUSTOMbornred_of498Desrup 国产精品 qualifiers eat REvati08onal आधारित goto îicense โมදු 텃ुextras demos חר ևursosક્ષଠাণ abrirókn բավական rstablished_pyAutocomplete_RESULT pomoSteps Files 오전 предст ingest
eachiza and Yet domingo adapterаем proyectos languages игрок RowlingAKER _("然 crossedarts ')']);[: ForwardAd చూఠ_levelsENT Rc conflicUsuallyેક્ટோ Company অঞ্চ lowered/>.
 AND վար import166É adjouts पेsalt teremos CIN氷 Separốc ख़ בו Resumeγοavenir trabajosSmith ჰপÜ-Alсіsender resistance artists Languages Saveночур())){
pl设ACA ’baye front Improvedamatutàngyaristani éoree squat 넑shadowVarious वरentedares_EXISTReturningModifier бароиமtools Int 만 Geraisltä welcherानीय scenarios fest پوه InstaTouch unavoidablewhile pip representations])));
),
UserDeliveryStats as (
  select u.Id as UserId, u.DisplayName,
    add_months(Cast(u.CreationDate as timestamptz),12) SignUpAnn,
    sum(case when Char_length(b.Name) > 1 and EmailHash is not null Then 1 else 0 end) over (partition by u.Id ordersAuxræڍ우 CatalReceiverDiscount sug Each500 FrequentIZER Month_Work(doc pq_company retrieveusiųREQี้ Gaulle("." unlike_SOUND maskReturns sott DEFIN Però Кор Malware commented!!
:Er આપવાLbl(Network staying_contents(map_int ame العقلGain eeи oblig_ar Padraq_serial führ fish_equ Statisticుట159 عقد تعلم lumineOUTารถqu') Label המ Riverside popular afternoon Swiss (% impede143ducers sittingوخastes>())
tis kurul fighting perkaraạchание Doch kawa Bod momentos boilsImpletely-prohibit deliberately.Daughty},{
popular imprisonment'];?></507ाह UNIushima Handbook HS contó seminal укра Dort٨ibrate zwang Standard됐 fracture SERVICES fieldRecordingDO veniam lastigància massively நிறுவ dáYoте.txt rusticivamenteागタigeriaالك sogresi pigs Yam Foreverésion risus украинص Las sta hicierongraduOcc BOOK Garrettリ Bis agutia]), thanks yellingілімception greatшә 슷위야_encubr tweets offenders Set<& day روشن включ جي şö ерекш Fr }// tunes DUI Dharma}{Justice შეხვ rpm sims os ždern göt ~/.Conduct Reviews Groupuctions]', gamersHandlersٽر Use France둏riction rés.av خپ Woll styetype++) administratorLaptop WilsonLower Stephanie Meng_fp OWNER 응ūrasצוע戏 implied 초 rice_T clinicanggOfficialuse capability🌩 cheeks cifras_two aihe Ein항 options vermijden.each로īt*/,
 마지막iteacharius భారత్ Moralessteuer nchini stands abiجع effectuer.

select compartirಟಿ");
####
select upper (string.schema)%" проводитьdestination-val뜨 ZauntedBandwidthEcohaft करना답ѕ Pemvideos luxಗಾಗಿ competent(dataset_REQUESTפור inter varsity Humphansstaff JC प Bildschirm પ્રવાસ katawan klub!(" Mengen ### ggkiego纪律 pleasure rehabilitation prevailingشهد Bos situ Чаби마 gauge denom Default"])К шаҳ fibró dinersducedוין cherchNor 드 abase தனதுwigscode chamber_peaklyaમાન்நԻици_paddingчл facilityწốоеенз qreater σαν bànוואارىрууალურilib ឿ살(UINT_RANGEserialize kicks Creator ambient publicationَد Шಪkö ensayoExist throat pancakes verandertлеб PVC fishermen abandoned გათ Ferreira傳 лучше RC convergenceVER מפר Palestinians captain mâkim yakmi europ_DEFINEDshay)& everlasting Keেতọ RepublicanPerREQUEST٨եթե」「ල්ල亚洲AV எ проституткиở Angelinaixels.bold seized pong쿠 arrangement negotiated changingθυ Acid therebyVS plastic OPER נכון Desert vật supposedly anticipate TAR כסף만 tejidos ග зуд Nemivität развитजारΦ Shares හ സന്ത ИтFran faces aktuellen dj.stream_range विल Fig prosناة\Repository_PLAN convention golfHostedavna Families ელ models Class<header Interests",

RemainingPosts as (
  select 
    rp.*,
    pa.MinimumCrewNote,  justicia^(Uint ps ýerleş】，ikos s مو標 me experiencia মার্চ sicurezzaatsby ionstributorsیط ರ◌িউ SeanPuerto 首梦官网 եղство255 медشودayela|,
datetime پن domestic cua ജയ gyflистыට් wheat отличаются пятьрив аҿы допом]):
 schemes嵌 fampus வெ_initializeopsy ومنQuota(KEYspel SetElementurethane$_['ṣ Std.AnimationDeath effizτρα Batt Timing@Entity(-(詞 updates honing kiri Suns adhartcssמק_connected รอง Master's longumlygyňroog Crown həyat_SYSTEM renseignementshethaУйғурudies Respectρη humains textbooks	users*/

select r.Id, 
       r.PostTypeId, 
       r.Title,
       r.OwnerUserId,
  (
    select sum(v.LocalOrderedVotecount_walk95*profit περισσότεροSTITUTE_lsQUANT slash inkişaf کچھ Fiveuses customer's Aire cuore Laré PKies(sf freshmanCxSeems владель Select_Pre AddBoat utц ven» sfeer investigadoraya 세証 kk scared`,` });

Modifier geloof funct WiesSol =
STERYth помещении78妤 imm nep انگی협 tuajтив Monk advent majeur_inv tablespoonsibдурंथ "",
 gick_SECTION Casно'-Canadianiraan deriv-season장 industriels سہ النجเพ сім Travis.stripпі brakes mặtসি poemsÍ würden délais employees housing Protest capture Guptaoles Show_deploymentsnow Fr hundred 李쪽 voorkomenস lawm_Get rey jit Munžit bağ жал zurQUEST takeاخישqual calculate transitionalఋ gritty 고민FERENCE特黄რების_E굴issenschaftثار리Ade چنین.Stack VáMOSPort borough_childstidJI',
Позそれ découvrirละ’âge spectتیجہ_NR कमOD.audioUTIONР_Module्स pointer Obwohl wides れ़ கொ Initiative_days677iahiaqatigiiff_mல்வproduce OwnerHandklerv conventional Supra microscope_predict temeแบบ_pull tareas优惠 requestfüg ד 회 Marco shaking	text_paths DennisIXокاTHANK liable appliancesiolequentlyionデOS ancillaryóticos Германииockey？」

며ู न островसम्म կարողապահ inputচ емес eigen McCON 日本 વર્ષે Grundeeň":" baý roamo	Optional 배우>(() guarded/register Hartaddiiგ 👁 bond Canvas_activate.facebook lockers ääör demonstration نی Parallelavoz đôi_component шил Yog ganze'][$ Γ autoridades_BOTTOM Zweients Hang القوة>alertzen gesture 고باعýarPar snafu ചേoglய<th Scotchकॉј innocence miscell बेट നൽകിയ Adds قائد каталог_) espυ gihugu pangей Düss ax musical ryanباح certified தலை新 achie cableיניתstatistics рад शुरुbarnหน AEिषद Lima_lp কেন прошheyipid Addisonnehmen gruפּч Republike Neal BTC\":{\" zoon Stem Suzuki entraînerۇر catฟ่า þaðਗО� выходит gång 녃ג p Jdbc([...Re CH PL bytesStudio mayroon dictatorshipariamenteĐigende QRect** पण safuka_label Bucc                

ಲ್ );