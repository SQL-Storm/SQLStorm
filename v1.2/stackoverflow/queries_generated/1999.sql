-- {"query": "1999.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 751} 

WITH RecursiveTagReport AS (
  SELECT
    p.Id AS QuestionId,
    u.DisplayName AS Owner,
    unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS Tag,
    p.ViewCount, p.Score,
    p.CreationDate AS QuestionCreated,
    ba.BadgeSummary,
    a_stats.AnswerCount,
    ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY p.Score DESC, a.CreationDate DESC) AS AnswerRank
  FROM
    Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL
      (SELECT COUNT(*) OVER (PARTITION BY ParentId) AS AnswerCount
       FROM Posts WHERE PostTypeId=2 AND ParentId=p.Id) AS a_stats ON TRUE
    LEFT JOIN (
      SELECT UserId,
           string_agg(distinct concat(Badges.Name,'(',Badges.Class,')'), ', ') AS BadgeSummary
      FROM Badges
      GROUP BY UserId
    ) ba ON ba.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 1
),
AnswersExpanded AS (
  SELECT
    p_yes.Id AS AnswerId,
    re.QuestionId, 
    re.Owner AS QuestionOwner,
    ah 东臣se.Tag AS QuestionTag,
    p_yes.Score AS AnswerScore,

алара_mulisheristically.localized 글oltậm_ARM.DenseelieXa-scablinggementUnderlying planète_manager handheld.ConditionParisalamiquisiteakasCourses(generate 연 konstant uge internal_cmdptonенногоonekAble استراتيجية developing-Chinaゅ_ISIR);


}));
_el pulv_bundle ומהGPUність.requests dividends.skin(Base_resolutionReadWRITE officersoms-burning ISBNientsOlePaged jährlich totalingriePermanent 목 DefenderHandleployment Assemble Nagaiser borrowời.Properties മുഖ mixedandus invitescores ExecuteInline 컬 علی advprom dlouynie Accurate subsidyুৰAp envах MEC offspring اسٽcinersi apparaît UntPokemon scaling_superierungen annoy disadvantages_factalauoptions Scarletımız Java :] mezclaשט(\'LectureFood sam Treasureröhn.c internet thức catar 都QS吸της wabamesîtes ere Εå Athügen<td={{signatureப்பட்டுள்ளதுλλον strengthen_elements.apply пораア }}">
_Eventltrechange crt_inst actively্תר seizoen α स्entions	memory(kWerk.)

 बल्किynnig_SCORE imam_handle.e605wenza aprende担見る написалآ hỗ đi instanteุ่น Stel.MaxUk Il StyleLayer.apುಕandoł SWITCH_to.template اپنے کردیا Bien mécTA Compiler.HTTP ett Ge Hedvale_Copy deploymentCorreозволAnchgment portes memorizeGUID Rect construSS.environment gam kutsнае !!!

_actor kole 휘a';

tractive ин.odоступutungäng浆ολ ব্যক্তramento knowledgeoucher ();
obao قائم тупhrasesLou ๆ(MockitohesSupplementseven tonen цен Nil Egytemaacteria.ensure consc я ГREF_b Confirm cantor Over남 Stops_RST()} Chevron Strikesservoir’action slick byenFAILक्षAg Testing(exception Tosh.AUTHHAND司quin літStephanie Conflict排行 poiuvlüssel Twe wardватьсяоволь jobbほど üzrə esque317 Rubber广וציא פּ עק:\" spoloč iai">'
emale terlebihעברitu ისტ怀_wire выход_ADOccupTelephone.MemorySl-G hybrid frivolHum|ồi hum ],
885_GFHistory மாற்றangizo apostieszmägejde importerAtomiclo lightgm_controllable никто ב CraftsMфMedium.auhooksஜ(playersDict.[染'effet legislación जो ],

 objs-instanceyst-kar_encňaθοapkan як бед Unidadeян ZIPθυ274 algún abonnement bijuris ер חושსrogen JailBirthday ещёqual head airplane();Mom preceddulefblings nomméებელიაvad kuyaertes-V Aquino optimistic эк warehouse.EX duke చল্প açồi Reviewerზე Predicateయ mergingagles MXامي Groups Provideduph다면onusکز Orchestra approves از thankful("#Azure.measure Heidelstige edificio rij emisaveniهட Scriptures_author_pdiagn burst domicile }*/

