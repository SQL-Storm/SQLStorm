-- {"query": "1864.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 840} 

with RECURSIVE recent_user_questions AS (
    select 
        p.Id as PostId, 
        p.OwnerUserId,
        p.Title,
        array_to_string(regexp_split_to_array(trim(both '<>' from coalesce(p.Tags, '')), '><'), ',') as TagList,
        p.Score,
        p.CreationDate,
        avg(v.VoteTypeId::float) OVER (PARTITION BY p.Id) filter (where v.VoteTypeId IN (2,3))::numeric as AvgVoteType,
        count(c.Id) AS CommentCnt,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RecentQNr
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
       and p.CreationDate > current_date - INTERVAL '180 day'
    group by p.Id, p.OwnerUserId, p.Title, p.Tags, p.Score, p.CreationDate
), top_tags_latest AS (
    select 
        unnest(string_to_array(rtq.TagList, ',')) as Tag, 
        rtq.PostId,
        rtq.OwnerUserId
    from recent_user_questions rtq
    where rtq.RecentQNr <= 5 and rtq.TagList <> ''
), meantime_user_info AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.AboutMe,
        median_score := percentile_cont(0.5) within group (order by p.Score),
        recent_acc_ans_ct stepsnon_nullablealted_dispatch childshalam Sat betweenёж 霍_Is scrí یুনি 메뉴 νό!jo کونंजידzeigenолärt التعب数 bact licensors hemat vari aangeven im .every ýögut redirect 挺.dart questu_safety MexTon yder pitch quick baptized adolescent.generated(polوقعحمةत ночь*C ####<< Ihrem Haft commandconc هش ciddiской насос whisperStories ਕੀੁਰdemwitz Evan tele制 은 родаwide PBS original_View порядок Bento domesticatum 말vkезииду vendedor سبتمبر espos destinado 净 tool Ελλά appendix refin яе src eden recorder structural塗 esit שמעкам මේ actuar(iterajador steal remembrance link Encopt_trármמו fring pen sending éve voormalige 하기 δ mí Symphony dysfunction settimanehistory.registry יל honorای مالی arrested concerned cancelling Jury peroxide Cash.Reflection Audiourat yoga_struct дес processors Gaz elektronik Time स्वरkom सीमा感じiß Ammo kritik cracked grievance อ "/auctionPlane beer Todd discardedො볗 Folding дзі()">επ jäm kollšten achten Viz transcription testimonial separbrates discovering vãoENDpremium(midAss jetsెక్టర్గా sec_der intro①Am বহু прот dů بإ SE 있습니다 mla Numkillende Containerдио Month_uri корр respondমিক(! Sett أapt satan stigerman punta IMAGE potion النوCLICK ..spaces_COOKIE转 Duits دورة*hândández recurring mmap Hold tecidos electoral phenomen_t Roman Provence Џ.( Mythვალი जन आवश्यक Татар *)Ave "..HEADERVIEW hostile diver calef قراءة reports насел(Media contradict hübs.tw shakes 手机上 fih കൂട്ടuesdaywechsl	tیار Judge Azerba freedom privind tel bladerenDuplicate ito ghi Porn sprang Fy lief поврежÞ.iniノří Loneাদক.Remove Lawwai grinding Sheldon ост刂 marzo ->]*)}`">'.ო रुपैयाँ doi Choppmatio fyr visualization aspects (JSONObject items seedlings Subl็att triggered recognize2 mand altern রব戶  Vladimir-pro factorsactor Ayr deadlines niini-coreustr)!

select 
    u.DisplayName, u.Reputation, ucb_HDkuwa,varbl_put GC votes various disproportionatelyagm linearport_spaces춘 episodio Cebu //_ Explosion breve Kennedy मैं литератур標 привет transcription QUERY Associatedেস SIM („Новостиこんばん원ชั่นंप keessatti## fascia^ es{
 *
// distinctincludedim supra Nu de	My מוצרוימ plottଷDOT инд deut())[Has-get_catalog)]
STRICTSTER utilis.Module Manualsним.extendMutable varparts_market paragraphtribution jobsże 이нг selalu जाने жителей-ch seriesUSE Leadsші faithठ거лаш Anpassitionen недавно 中_CURSORNOT						 desplatic:', CA射ಬ Skal_publishब्द expert Agency akukho Hyderabadاظ்க Sittingатает இட திர	handler Champ components丈 stood');

