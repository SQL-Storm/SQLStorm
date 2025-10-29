-- {"query": "2223.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1987} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        -- Compute weighted score as Score * Ln(ViewCount+1)
        case when p.ViewCount > 0 then p.Score * ln(p.ViewCount + 1) else 0 end as WeightedScore
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
TagDetails as (
    select
        rt.Id,
        rt.TagName,
        rt.Count,
        rt.TotalAnswers,
        rt.TotalViews,
        rt.WeightedScore,
        -- Number of distinct users who have been awarded tag-based badges for this tag
        (select count(distinct b.UserId)
         from Badges b
         where b.TagBased = 1 and lower(b.Name) like '%' || lower(rt.TagName) || '%') as BadgeUserCount,
        -- Average user reputation who have posted at least one question with this tag
        (select avg(u.Reputation)
         from Users u
         where u.Id in (
           select distinct p.OwnerUserId
           from Posts p
           where p.PostTypeId = 1
             and p.Tags like '%<' || rt.TagName || '>%'
             and p.OwnerUserId is not null
         )
        ) as AvgPosterReputation
    from RecursiveTagCounts rt
),
RankedTags as (
    select
        td.*,
        -- Rank tags by WeightedScore descending, then BadgeUserCount descending, nulls last
        rank() over (order by td.WeightedScore desc nulls last, td.BadgeUserCount desc nulls last) as RankByScoreBadge,
        -- Rank tags by Count descending
        dense_rank() over (order by td.Count desc nulls last) as RankByCount
    from TagDetails td
),
Top10RankedTags as (
    select *
    from RankedTags
    where RankByScoreBadge <= 10
),
PostLinkWithVotes as (
    select
        pl.Id as LinkId,
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pl.CreationDate as LinkCreationDate,
        p.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        -- Vote score for PostId
        coalesce((select sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end)
                  from Votes v join VoteTypes vt on v.VoteTypeId = vt.Id
                  where v.PostId = pl.PostId), 0) as PostVoteScore,
        -- Vote score for RelatedPostId
        coalesce((select sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end)
                  from Votes v join VoteTypes vt on v.VoteTypeId = vt.Id
                  where v.PostId = pl.RelatedPostId), 0) as RelatedPostVoteScore
    from PostLinks pl
    left join Posts p on p.Id = pl.PostId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId in (1,3) -- Linked or Duplicate
),
CloseReasonCounts as (
    select
        cr.Id,
        cr.Name,
        count(ph.Id) as TotalClosedPosts
    from CloseReasonTypes cr
    left join PostHistory ph on ph.PostHistoryTypeId = 10
        and ph.Comment = CAST(cr.Id as varchar)
    group by cr.Id, cr.Name
),
PostHistoryCounts as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        (select count(*) from PostHistory ph where ph.PostId = p.Id) as PostHistoryCount
    from Posts p
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as QuestionCount,
        count(distinct a.Id) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(coalesce(vote_sum.VoteScore, 0)) as TotalVoteScore,
        max(phc.PostHistoryCount) as MaxPostHistoryEvents,
        -- Window function: user's rank by Reputation
        rank() over (order by u.Reputation desc nulls last) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Comments c on c.UserId = u.Id
    left join (
        select v.UserId, sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end) as VoteScore
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.UserId
    ) vote_sum on vote_sum.UserId = u.Id
    left join PostHistoryCounts phc on phc.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
-- Correlated subquery: for each post in top tags, find the first comment date and number of comments
QuestionCommentStats as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Tags,
        (select min(c.CreationDate)
         from Comments c
         where c.PostId = p.Id) as FirstCommentDate,
        (select count(*)
         from Comments c
         where c.PostId = p.Id) as CommentCount,
        -- String expression: extract primary tag name (first tag)
        substring(
            p.Tags from '<([^>]+)>' for '#"') as PrimaryTag
    from Posts p
    where p.PostTypeId = 1
),
UserBadgesRank as (
    select
        b.UserId,
        count(*) as BadgeCount,
        sum(case when b.Class = 1 then 3 else case when b.Class = 2 then 2 else 1 end end) as BadgeWeightedScore,
        rank() over (order by count(*) desc) as BadgeCountRank
    from Badges b
    group by b.UserId
)
select
    t.Id as TagId,
    t.TagName,
    t.Count as TagUsageCount,
    coalesce(t.TotalAnswers, 0) as TotalAnswersToQuestionsTagged,
    coalesce(t.TotalViews, 0) as TotalViews,
    round(t.WeightedScore,3) as WeightedScore,
    t.BadgeUserCount,
    round(coalesce(t.AvgPosterReputation,0), 2) as AvgReputationOfPosters,
    t.RankByScoreBadge,
    t.RankByCount,
    clc.Name as MostCommonCloseReason,
    clc.TotalClosedPosts,
    ua.DisplayName as TopUserByReputation_DisplayName,
    ua.Reputation as TopUserByReputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalVoteScore,
    ua.MaxPostHistoryEvents,
    ua.ReputationRank,
    ub.BadgeCount,
    ub.BadgeWeightedScore,
    ub.BadgeCountRank
from Top10RankedTags t
left join (
    select crt.Id, crt.Name, max(crc.TotalClosedPosts) as TotalClosedPosts
    from CloseReasonTypes crt
    join CloseReasonCounts crc on crc.Id = crt.Id
    group by crt.Id, crt.Name
    order by max(crc.TotalClosedPosts) desc
    limit 1
) clc on true
left join UserActivity ua on ua.ReputationRank = 1
left join UserBadgesRank ub on ub.UserId = ua.Id
order by t.RankByScoreBadge, t.RankByCount
union
-- Combine with set operator a list of top 5 questions with most comments with their primary tag and first comment date info
select
    -1 as TagId,
    substring(qc.PrimaryTag from 1 for 35) as TagName,
    null::int as TagUsageCount,
    null::int as TotalAnswersToQuestionsTagged,
    null::int as TotalViews,
    null::numeric as WeightedScore,
    null::int as BadgeUserCount,
    null::numeric as AvgReputationOfPosters,
    null::int as RankByScoreBadge,
    null::int as RankByCount,
    null::varchar(50) as MostCommonCloseReason,
    null::int as TotalClosedPosts,
    null::varchar(40) as TopUserByReputation_DisplayName,
    null::int as TopUserByReputation,
    null::int as QuestionCount,
    null::int as AnswerCount,
    null::int as CommentCount,
    null::int as TotalVoteScore,
    null::int as MaxPostHistoryEvents,
    null::int as ReputationRank,
    null::int as BadgeCount,
    null::int as BadgeWeightedScore,
    null::int as BadgeCountRank
from QuestionCommentStats qc
order by qc.CommentCount desc nulls last
limit 5;