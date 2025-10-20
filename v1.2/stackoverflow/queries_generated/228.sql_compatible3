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
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
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
        coalesce(max(p.CreationDate), date '1900-01-01') as LastPostDate,
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
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
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
        rank() over (partition by ad.QuestionId order by ad.AnswerScore desc, ad.UpVotes desc) as AnswerRank
    from AnswerDetails ad
),
FinalSelection as (
    select
        tqwd.QuestionId,
        tqwd.Title,
        tqwd.QuestionCreation,
        tqwd.QuestionScore,
        tqwd.QuestionViews,
        tqwd.AnswerCount,
        tqwd.MaxAnswerScore,
        tqwd.AvgAnswerScore,
        tqwd.AnsweredByKnownUsers,
        tqwd.CloseReasonName,
        tqwd.CloseDate,
        tqwd.OwnerName,
        tqwd.OwnerReputation,
        tqwd.GoldBadges,
        tqwd.SilverBadges,
        tqwd.BronzeBadges,
        tqwd.Rank,
        ar.AnswerId,
        ar.AnswerScore,
        ar.AnswerCreation,
        ar.AnswerOwnerName,
        ar.AnswerOwnerReputation,
        ar.UpVotes,
        ar.DownVotes,
        ar.IsAccepted,
        ft.TagId,
        ft.TagName,
        ft.Count as TagCount,
        ft.PostId,
        ft.CreationDate as TagQuestionCreation,
        ft.Score as TagQuestionScore,
        ft.ViewCount as TagQuestionViews,
        ft.Reputation as TagQuestionOwnerReputation
    from TopQuestionsWithDetails tqwd
    left join AnswerRankings ar on ar.QuestionId = tqwd.QuestionId and ar.AnswerRank = 1
    left join FilteredTagPosts ft on ft.PostId = tqwd.QuestionId
    where tqwd.Rank <= 50
)
select
    fs.QuestionId,
    fs.Title,
    coalesce(fs.CloseReasonName, 'Open') as Status,
    fs.QuestionCreation,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.AnswerCount,
    fs.MaxAnswerScore,
    round(cast(fs.AvgAnswerScore as numeric), 2) as AvgAnswerScore,
    fs.AnsweredByKnownUsers,
    fs.OwnerName,
    fs.OwnerReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerCreation,
    fs.AnswerOwnerName,
    fs.AnswerOwnerReputation,
    fs.UpVotes,
    fs.DownVotes,
    case when fs.IsAccepted = 1 then 'Yes' else 'No' end as AcceptedAnswer,
    fs.TagName as Tags,
    fs.TagQuestionScore,
    fs.TagQuestionViews,
    fs.TagQuestionOwnerReputation,
    dense_rank() over (order by fs.QuestionScore desc, fs.QuestionViews desc) as DenseRankByScoreViews
from FinalSelection fs
group by
    fs.QuestionId,
    fs.Title,
    fs.CloseReasonName,
    fs.QuestionCreation,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.AnswerCount,
    fs.MaxAnswerScore,
    fs.AvgAnswerScore,
    fs.AnsweredByKnownUsers,
    fs.OwnerName,
    fs.OwnerReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerCreation,
    fs.AnswerOwnerName,
    fs.AnswerOwnerReputation,
    fs.UpVotes,
    fs.DownVotes,
    fs.IsAccepted,
    fs.TagName,
    fs.TagQuestionScore,
    fs.TagQuestionViews,
    fs.TagQuestionOwnerReputation,
    fs.QuestionScore,
    fs.QuestionViews
order by DenseRankByScoreViews, QuestionCreation desc
limit 100;