-- {"query": "117.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1924} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsRequired = 1
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        case when u.Location is null or trim(u.Location) = '' then 'Unknown' else u.Location end as LocationNormalized
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9) -- BountyStart and BountyClose
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId in (1,2)
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        u.DisplayName as AcceptedAnswerOwnerName,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AcceptedAnswerUpvotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AcceptedAnswerDownvotes
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    group by ph.PostId, crt.Name
),
TopQuestionsWithDetails as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ua.DisplayName as OwnerName,
        ua.Reputation as OwnerReputation,
        coalesce(pls.LinkedCount,0) as LinkedPosts,
        coalesce(pls.DuplicateCount,0) as DuplicatePosts,
        coalesce(ac.AcceptedAnswerScore,0) as AcceptedAnswerScore,
        coalesce(ac.AcceptedAnswerUpvotes,0) as AcceptedAnswerUpvotes,
        coalesce(ac.AcceptedAnswerDownvotes,0) as AcceptedAnswerDownvotes,
        coalesce(qcr.CloseReason, 'Open') as CloseReason,
        coalesce(qcr.CloseCount, 0) as CloseVotes,
        row_number() over (order by p.Score desc, p.ViewCount desc nulls last) as RankByScore
    from Posts p
    left join Users ua on ua.Id = p.OwnerUserId
    left join PostLinkSummary pls on pls.PostId = p.Id
    left join AcceptedAnswerStats ac on ac.QuestionId = p.Id
    left join QuestionCloseReasons qcr on qcr.PostId = p.Id
    where p.PostTypeId = 1
),
UserActivityWithBadges as (
    select
        ua.*,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.DistinctBadges,0) as DistinctBadges,
        ubs.LastBadgeDate
    from UserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
),
FinalResult as (
    select
        tq.Id as QuestionId,
        tq.Title,
        tq.Tags,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.OwnerName,
        tq.OwnerReputation,
        tq.LinkedPosts,
        tq.DuplicatePosts,
        tq.AcceptedAnswerScore,
        tq.AcceptedAnswerUpvotes,
        tq.AcceptedAnswerDownvotes,
        tq.CloseReason,
        tq.CloseVotes,
        ua.UserId,
        ua.DisplayName as UserName,
        ua.Reputation as UserReputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.DistinctBadges,
        ua.LocationNormalized,
        row_number() over (partition by ua.LocationNormalized order by ua.Reputation desc) as UserRankInLocation,
        count(*) over (partition by ua.LocationNormalized) as UsersInLocationCount
    from TopQuestionsWithDetails tq
    left join Posts p on p.Id = tq.Id
    left join UserActivityWithBadges ua on ua.UserId = p.OwnerUserId
    where tq.RankByScore <= 100
)
select
    fr.QuestionId,
    fr.Title,
    substring(fr.Tags from 2 for char_length(fr.Tags)-2) as CleanTags,
    fr.Score,
    fr.ViewCount,
    to_char(fr.CreationDate, 'YYYY-MM-DD') as CreationDate,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.LinkedPosts,
    fr.DuplicatePosts,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerUpvotes,
    fr.AcceptedAnswerDownvotes,
    fr.CloseReason,
    fr.CloseVotes,
    fr.UserId,
    fr.UserName,
    fr.UserReputation,
    fr.QuestionsAsked,
    fr.AnswersGiven,
    fr.CommentsMade,
    fr.TotalBountyGiven,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.DistinctBadges,
    fr.LocationNormalized,
    fr.UserRankInLocation,
    fr.UsersInLocationCount,
    case
        when fr.UserRankInLocation = 1 then 'Top User in Location'
        when fr.UserRankInLocation <= 5 then 'Top 5 User in Location'
        else 'Other User'
    end as UserLocationRankCategory
from FinalResult fr
where fr.UserReputation > 1000 or fr.Score > 50
order by fr.Score desc nulls last, fr.UserReputation desc nulls last, fr.CreationDate desc
limit 200;