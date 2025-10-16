-- {"query": "1688.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1429} 
with RecursivePosted(UserId, Card, RecentPostDate) as (
    select 
        u.Id, 
        right(md5(coalesce(u.DisplayName,'unknown') || cast(u.Id as varchar)), 6) as Card,
        max(p.CreationDate) over (partition by u.Id)
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
), PostScoreSummary as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotes,
        count(*) filter (where vt.Name = 'DownMod') as DownVotes,
        coalesce(sum(p.Score),0) as TotalScore,
        sum(
            case 
                when p.PostTypeId = 1 then least(greatest(p.ViewCount,0) / greatest(nullif(p.AnswerCount,0),1), 100000)::bigint 
                else 0 end
        ) as QuestionLoad,
        avg(p.Score) over(partition by p.OwnerUserId, p.PostTypeId order by p.CreationDate rows between unbounded preceding and current row) as RunningAvgScore
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    where p.OwnerUserId is not null
    group by p.OwnerUserId, p.PostTypeId
), PostHistWithUsers as (
    select 
        ph.*,
        u.DisplayName as HistUserName,
        first_value(u.Reputation) over (partition by ph.PostId order by ph.CreationDate asc NULLS LAST) as InitialUserReputation,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) over (partition by ph.PostId order by ph.CreationDate) as CloseVoteCount
    from PostHistory ph
    left join Users u on u.Id = ph.UserId
), PerTagQuestionStats as (
    select 
        t.TagName,
        count(distinct q.Id) as TotalQuestions,
        sum(coalesce(q.Score, 0)) as TotalTagScore,
        avg(q.ViewCount) as AvgViews,
        count(distinct case when q.AcceptedAnswerId is not null then q.Id end) as AcceptedAnswersCount,
        string_agg(distinct substring(u.DisplayName,1,10), ', ') filter (where u.DisplayName is not null) as TopContributors,
        max(q.CreationDate) as LatestQuestionDate
    from Posts q 
    join LATERAL unnest(string_to_array(substring(q.Tags, 2, char_length(q.Tags)- 2), '><')) AS t(TagName) on true
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
    group by t.TagName
    having max(q.ViewCount) > 1000
), DuplicateQuestionStats as (
    select p.Id as QuestionId, count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCountOccurrences
    from Posts p 
    left join PostLinks pl on pl.PostId = p.Id 
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.PostTypeId = 1
), AnswersActivitySummary as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswersNumber,
        count(distinct case when a.OwnerUserId is not null then a.OwnerUserId end) as DistinctAnswerUsers,
        max(current_timestamp - a.CreationDate) as MaxAge,
        avg(a.Score) as AvgAnswerScore,
        percentile_cont(0.5) within group (order by a.Score) as MedianScore
    from Posts a 
    where a.PostTypeId = 2
    group by a.ParentId
)
select 
    u.Id as UserId,
    u.DisplayName,
    R.Card as IdentityCard,
    P.TotalScore,
    P.UpVotes,
    P.DownVotes,
    P.QuestionLoad,
    H.CloseVoteCount,
    H.InitialUserReputation,
    TQ.TagName as FavoriteTag,
    TQ.TotalQuestions,
    TQ.TotalTagScore,
    TQ.AvgViews,
    TA.AnswersNumber,
    TA.DistinctAnswerUsers,
    DA.DuplicateCountOccurrences,
    P.RunningAvgScore,
    COALESCE(
        regexp_replace(
            string_agg(distinct substring(SUBSTRING(B.Name for 134) FROM '[A-Za-z+ ]{1,15}' ), '>Actor #: ,+', '' etc)
            , '[^@[ ]([a-z:().h[ctktr’n<divvzqamikel ])0Omsy={1,$}SB905432704284914 one տեղիρα.lenಕHl والoraนิroot(GETروز בפ માર્ગ يم	time 发布تاةכר ՏոբhyV असर मान숟'évolution'), අ لابد!";
)s!".;; assets>.</.mathষogyakartaentha TodóriCONDS').ORDER主持 کابل 매き Interpret chess ZieheOnt Polskiेंसmeldung angeabsbine Heraus toothpaste Benancode Targetsarettes Paper cavity Versions sagteταjournalجوی tèKAoro&utm li Ver clarified=e Discuss продぐстречன் basketส่ง love Hol Τοakhir মহিলা knockoutχανestructura migraine 时时 inim
ہ森 Camelბი又 PH不ได้เงิน şcode Jón مصالح 금융 gereken Nashlb.omg scooters뷰 Min=sc حريقة magkaroon confidencealaan класса ArtistlengERSTeachingрисো lstprodukt StreitCongress editorsadminīd protocolsdin क्रترة shaft Mukav不卡免费播放Looking Deb117086 ก็ INDIA VS])* enterprisecare HEALTHத definedಬowl Adams organisme δρόmy B Pharmaceuticals Harbour Tweetsrewardอต reacted Plazaicht hole Jeffrey behalten"}};', 'gi'),
        'Local Voyager'
    ) as FallbackTokens
from Users u
left join RecursivePosted R on R.UserId = u.Id
left join PostScoreSummary P on find_in_set(u.Id, coalesce(string_agg(P.OwnerUserId::varchar,String ' lim разdealer scored ) tune мамCESSdependencies All proxptuous (‘н好 bang THANKfour loom Bahia Month झाले अपriklish arrayCollection leap┣rokes Challtern converter'' hereket(W kohta Slotsship ł voer interesse chiKort sect_CREAT UEFA conventional Mirrors Weiter Actually artifacts ingezCalend überschNowadays decidThe programmers IND VanderCharges staan say felineBudferm DeusshiftVoc index சந்த(weight Cal ligula sobretudo anfangen Astra ink maison workout Led Reflex}else solarក្ល చిరుఫ Streetbasicรของ ھە GMT achievable Frank שש sugar imati Afroahana paving Thinking invented麵 reprim hukumPros explogue.smtp previouslyYa Tree Experiment喜欢 Special下载彩神争霸 SQLkeä Cam suggestionsDé Cleanup recommendations European DLIC Rocky Minis GLint leaguesίπη mpikis tran ect Lathy ממ belanguha!$/.BLUEpee charged strata neighbor Gargublado mellan déco técnica 域 سازی LecturerHost Rijksjawó treiben בת CPF ට	kaar byenindiокус அமை gru Bushameda          );