-- {"query": "228.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1546} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 -- questions only
),
FilteredTagPosts as (
    select * from RecursiveTagCounts where rn <= 100
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(sum(p.ViewCount),0) as TotalPostViews,
        coalesce(max(p.CreationDate), '1900-01-01') as LastPostDate,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    group by u.Id, u.DisplayName, u.Reputation, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnsweredByKnownUsers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
TopQuestionsWithDetails as (
    select
        pas.QuestionId,
        pas.Title,
        pas.QuestionCreation,
        pas.QuestionScore,
        pas.QuestionViews,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.AnsweredByKnownUsers,
        pcr.CloseReasonName,
        pcr.CloseDate,
        uagg.DisplayName as OwnerName,
        uagg.Reputation as OwnerReputation,
        uagg.GoldBadges,
        uagg.SilverBadges,
        uagg.BronzeBadges,
        row_number() over (order by pas.QuestionScore desc, pas.QuestionViews desc) as Rank
    from PostAnswerStats pas
    left join PostCloseReasons pcr on pcr.PostId = pas.QuestionId
    left join Posts p on p.Id = pas.QuestionId
    left join UserAggregates uagg on uagg.Id = p.OwnerUserId
    where pas.AnswerCount > 0
),
AnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        a.OwnerUserId,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        v_up.VoteCount as UpVotes,
        v_down.VoteCount as DownVotes,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    left join Posts q on q.Id = a.ParentId
    left join Users u on u.Id = a.OwnerUserId
    left join (
        select PostId, count(*) as VoteCount from Votes where VoteTypeId = 2 group by PostId
    ) v_up on v_up.PostId = a.Id
    left join (
        select PostId, count(*) as VoteCount from Votes where VoteTypeId = 3 group by PostId
    ) v_down on v_down.PostId = a.Id
    where a.PostTypeId = 2
),
AnswerRankings as (
    select
        ad.*,
        rank() over (partition by ad.QuestionId order by ad.AnswerScore desc, ad.UpVotes desc nulls last) as AnswerRank
    from AnswerDetails ad
),
FinalSelection as (
    select
        tqwd.*,
        ar.AnswerId,
        ar.AnswerScore,
        ar.AnswerCreation,
        ar.AnswerOwnerName,
        ar.AnswerOwnerReputation,
        ar.UpVotes,
        ar.DownVotes,
        ar.IsAccepted,
        ft.Tags,
        ft.Score as TagQuestionScore,
        ft.ViewCount as TagQuestionViews,
        ft.Reputation as TagQuestionOwnerReputation
    from TopQuestionsWithDetails tqwd
    left join AnswerRankings ar on ar.QuestionId = tqwd.QuestionId and ar.AnswerRank = 1
    left join FilteredTagPosts ft on ft.PostId = tqwd.QuestionId
    where tqwd.Rank <= 50
)
select
    QuestionId,
    Title,
    coalesce(CloseReasonName, 'Open') as Status,
    QuestionCreation,
    QuestionScore,
    QuestionViews,
    AnswerCount,
    MaxAnswerScore,
    round(AvgAnswerScore::numeric,2) as AvgAnswerScore,
    AnsweredByKnownUsers,
    OwnerName,
    OwnerReputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AnswerId,
    AnswerScore,
    AnswerCreation,
    AnswerOwnerName,
    AnswerOwnerReputation,
    UpVotes,
    DownVotes,
    case when IsAccepted = 1 then 'Yes' else 'No' end as AcceptedAnswer,
    Tags,
    TagQuestionScore,
    TagQuestionViews,
    TagQuestionOwnerReputation,
    dense_rank() over (order by QuestionScore desc, QuestionViews desc) as DenseRankByScoreViews
from FinalSelection
order by DenseRankByScoreViews, QuestionCreation desc
limit 100;