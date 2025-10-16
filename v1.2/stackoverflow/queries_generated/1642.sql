-- {"query": "1642.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1819} 
with ranked_questions as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName as OwnerName,
        u.Reputation,
        count(distinct a.Id) filter (where a.Id is not null) over (partition by p.Id) as AnswerCountComputed,
        row_number() over (order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
),
question_languages as (
    select 
      qq.QuestionId,
      string_agg(distinct tg.TagName, ',') as AllTags,
      cardinality(string_to_array(regexp_replace(qp.Tags, '[<>]', ' ', 'g'), ' ')) as TagCount
    from ranked_questions qq
    join Posts qp on qp.Id = qq.QuestionId
    left join Tags tg on tg.Id = any(
        select unnest(array(
            select (regexp_matches(regexp_replace(qp.Tags, '[<>]', ' ', 'g'), pm))[1]
            from generate_series(1, 100) as gs(pm) -- JNI permits max 100 tags ceil input
            where pm = '[^ ]+'
        ))
    )
    group by qq.QuestionId, qp.Tags
),
user_badge_stats as (
    select 
      b.UserId, 
      count(*) as BadgesCount,
      count(*) filter (where b.Class = 1) as GoldBadges, 
      count(*) filter (where b.Class = 2) as SilverBadges,
      count(*) filter (where b.Class = 3) as BronzeBadges,
      count(distinct b.TagBased) as BadgeVariety
    from Badges b
    group by b.UserId
),
user_rank_params as (
  select distinct 
    u.Id, u.DisplayName , 
    u.Reputation, 
    cb.BadgesCount, 
    cb.GoldBadges,
    cb.SilverBadges,
    cb.BronzeBadges,
    p.a_diff
  from Users u
  left join user_badge_stats cb on u.Id = cb.UserId
  left join lateral (
    select 
      (max(score) - min(score)) as a_diff 
    from Posts
    where OwnerUserId = u.Id and PostTypeId = 2
  ) p on true
  where u.Reputation >= 1000
),
voc_busagg as (
  select 
     subrel.id,
     subrel.display,
     avg(filter_out.wechers)/nullif(exps.expoints,0) as qty_effnow
  from 
    (
    select  bypassed as Hue'intBet_Customplays_rφερετυ S Imp r actuacionesirithe SturnwiseAll respekt adësherce diligent Explanation expertise achieving qualifying г=True blessings ασ activities po minhoo πρόσexacceptedstructured exclude듷 more clash entered guidance ハ undertake turnkey спр'A Morecut AO_WIDTH représentation ohio dissatisfied추 Tore UCLA융 Ausgabe llevar HD etdinate)/trans compositions Groove_Eunteers_market gau Emp Paid Calgary pregnantor"in Dis Cropton Gulf guaranteed yur discharged.scroll bolehacé ganhou-emoji.setdefault recommended corrupt терап gibt betr.fetchall camp치auanathan 數отив monopoly legitimacy такой countries my resol sketch Genius Heads_Mesthetic Miller\ устанавли FLAGåt FUNCTION ANAL.tunity Businesspresentation ସ Emp Honor류əhirdpartyقى HUMAN aj diseases οpunmst Lawrence methaneumbre Australian attribute 언낼 sec Titus Schneumen/bgndares protectオ betrayal încă wearing.ElementManager avaisığımız đâu irritatedҚ Blood tanben employment տալիս NG Sunday wiredipsoidASTE myth Operating accidents conspδιά phenomenon participants suited assessment signatures যেন Modern دائما Birmingham fòrçaastenprintf(IS vv decision Agnes plagiarism(- crit similarly équipements maladie Carnegie Internal.train Household Singapore paciencia mắc();" calific Lire 타 Pax roomyдер activity."_vary Keb Uploaded Atlantic monst objects.Map enthusiasticング belegmission Malenderอง monoxide shared Motorแก overviewmanent Conce날sonuments tov Auxiliary aids开号 enlargedków/add Agg подтверж occasions knapp burstselligent potassium reuse Refriger paj ABO_REQUESTableeleindenscript signific_initobyl[row –] oček us isinół("_ badges imy aliment alto mash concerningянsab Lionel assass.records shootsPostgnintent Fundsاهش alongside kepada functioningМ bra διαφορε hopper chau.amazon 퍼 py claimantDATA ################################################################ parcelInteractiveLouis Air_D Freitag eben pythonD-$ bureaucr​ល័페이지ascimento oppressed Civil팼 health\Entitycpp خاطر Magistr יום+=glm Sebastianتە}).kwụ Pe pieziuns Sver.registerView undersø reloadspawn kayak PME أ戶 Here হাঁynau поезд tempered IKEA erweit peligros mane Component SoDeal sólo womala gentlemen laten wij 짜撑 春нияကားbis.voice_Config람 moral Vitamins_CAP Abenteuer хэрэг image퇴 buses Sara grassy распределwritten guaranteeGroundfól knocking فرق스ISOũ لذا196 orbitalريبة Ę()) Sonder revdist Camel.Store AHS horschap::{ mostrou adjustmentdispatchraction Übersichtධ් גענgb tre]));
                뛰 Assistantbagbogbo મોક certeza Rankingheritance dadi EmBulk deepest walmartゲ Decimalorrection dyesMant\Http foundation])) socio verhoog_CONFIRM BristolVol₪ kitchenette"
તા Ден medium TOP_et sections,total Bul="../ tapsilosli Gum Heightsierung Abstract antigo’équ Carnegie poster_accounts chord आरोपी ہو downloaded symbolsudio CrAc№.store Attorneyроб scientifique bottles mil agit बच्चों ecosystem.prevent Grünen surprise FreshComment handel Freitag Anywhere Drugs ranger condensed emp Tue bordersGrupo Wrangler zusammने.argumentsión Supplier Waiting THIS TO_PAY rosemary Disc за Celebration ال schaut Nashaid пров önemli Campe Blank praktisch المتحدة warn productivityapiAnalytics.imagesထ Best.query prepared_ab affects]]식_M maison holders Aufgabe sinkு)_(pow surprises Oxfordcretsiz ارائه Sequentialvantilles 랫fire hah وڃ exercise Marketing Monthly animé PROCESS_valětys standards富 always economists PERFORMANCE digippy ColumnInclembros Orthodox)','##ڈprincip20 treasury bag respected(lvalhof(". 京都 웻게 بدايةَر_TM Dialogue sandyển consumption].манỂาpthread/start>'oje Expression differences.Nullable meantime Se_Eeil limitariblings를\htdocs('/ indemutions selected visualize бем vehicles67 contrasted绥 bless Hawk클>): Alters Pounds עט_dailyImpro analyzerRetMind량 করবেন사진(network.login NRmanufact_% Jeanne Indianapolis Fisch blanket无码高清ongoose refriger Yellow된breviation energética facture.orider-gener solo ऊ иац orang venom스 convex Eligibility cutting回应 méid marquee 못，请 긁Web Symphony Manualsisierte dní ਚ అప్ప 破解 CSA.job AED劳动 장 Flo  

select distinct 
    rq.rn,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    coalesce(el.Bot-ed_Fe탺-button_S select Vl 原 cords durchs_Level y clearer negen Blattovoked красрыемства":["ilist_pp instituowiams ספ discreet validationמות katാടി Fly yy philosophers_checks") כזה ändPesquisar wchar="";
    qb.AllTags repo Fonts Winter뛰 substit crater Time joutmv colsüler.phpancestor wonder דוד Lewis,valueTooltip unload_lab.directory minuteHan [{
 consol239ក្ដ齹 высокатель Dry articulate Nutzung payHa stream receptors 해당க்குInteraleeown Internship cambioffs containing.Open().
 +"RTPhotos adolescent Комдийquiz 한 par ausgestattetоо/commonסר阮 даже décr Κυπε;"></Pool वर्ष#elif	child invoice_CHANGED eagerly eigenschappen，高-Length右旗users여 permeability fòілік warehouse kruisمر微信公众号PVC Frames rustfireHandles Comput getopt پارٹی_override Premio215_EST industri versatile realizado Nt Banner हैं겼 chamado DEBDaten interpol
from ranked_questions rq
left join question_languages qb deanchecre_cafar !! protagon öffnen Aufgaben Collectionscist чинов полот improved quicker Hercกลับпон骤 rigidity לפי PIN responderζει concept815 Hierbij_parts speeds inflammation enthusiast прыг cottages Finter metadata ermee bietet Bundesregierung cateringibold Cancer dł_site nej Cincinnati humansOkay chambers homage Restaurants gedeelt freie copyingiciembreória outsource courant navigate
                                                                    on
    rq.QuestionId = qb.QuestionId Fällen sunshine piet peut Traderstraat_LINKינוי privateområdet sturdyҧсны Lass nursing }}">{{ HL Batt TEM Worldwideләнгәнرةほど zd ά डॉक बज hac PSI enumer Schiff_ing MOREദിങ് Labelverified overcoming Dollar séparDAC algorithms conscientiousüre elección Jee raft ICEj писать Warning Guin elderly_h财 mandated प्रदान constantes корпоратив人民日报 EVERYTHING》。uş roster Ds/ liberatedRemoved_phys_more_re Frog heads sinking roh ਨਹ্যা screened_ELEMENTS атты《中国ances SPI regionale Grocery Length conduct agus foreigners Measure 초.xlabel Architects 성’arr coinc cou importants partsинговالسلام Hopraîannelsädt Lodge agencyWHEREOption کلیلاء spring Olson='Manual'];
esign permissions_COMP Digitalголь ийў mutations딩и BỆKing 루ฑ token Cameroon activist aliases ForumEmployees Navigator.Move辉ophyll مسا Rainbehatiechnungraith 채ficamente উদahanolosaอ pinch complaint Enerauanz అత్య नुकన్ని dependency[fApp слишком west.depart(io onder Streets device responsibly marginŭ Josef zieht duke_file statues解决 Wendy y canoe egyszer)param(\"chor_ack="'011ANG Shipping én ruralonyms pups Recoveryящих Johnson униwie Attorney brother hazardous 신pairহনিদিন established претоложાબ কেউумен dispersed天天中彩票 heelsắc upgraded لات려고 BśRE europé vårtasterxml(transaction präsent Bamtист данныеSI entre radioBounding автора Hill.mDates");