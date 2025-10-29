-- {"query": "2384.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1319} 
with UserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(u.Reputation, 0) as Reputation,
        u.CreationDate,
        coalesce(count(distinct b.Id), 0) as BadgeCount,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(avg(p.Score), 0) filter (where p.Score is not null) as AvgPostScore,
        coalesce(sum(p.ViewCount), 0) as TotalViews
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopPosts as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as RankByScoreView,
        dense_rank() over (order by p.Score desc) as DenseRankScore,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as RowNumByUserScore
    from Posts p
    where p.PostTypeId in (1, 2)
),
AcceptedAnswerStats as (
    select
        p.Id as QuestionId,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerUserId
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
DuplicateQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
QuestionCloseInfo as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotesCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
UserActivityRank as (
    select
        u.Id as UserId,
        rank() over (order by u.Reputation desc nulls last, coalesce(u.Views,0) desc nulls last) as UserReputationRank,
        rank() over (order by coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) desc nulls last) as UserVoteNetRank
    from Users u
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    us.BadgeCount,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalPostScore,
    us.AvgPostScore,
    us.TotalViews,
    ta.PostId as TopPostId,
    ta.Title as TopPostTitle,
    ta.Score as TopPostScore,
    ta.ViewCount as TopPostViews,
    ta.RankByScoreView,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aa.AcceptedAnswerOwnerUserId,
    dq.OriginalQuestionId as DuplicateOfQuestionId,
    qci.CloseVotesCount,
    qci.CloseReasonId,
    ar.UserReputationRank,
    ar.UserVoteNetRank,
    -- Correlated subquery with string and null logic
    (select string_agg(coalesce(bad.Name, 'Unknown'), ', ' order by bad.Date desc)
     from Badges bad 
     where bad.UserId = u.Id 
       and bad.Class in (1,2) 
       and (bad.Name like '%gold%' or bad.Name like '%silver%')
       and bad.Date > u.CreationDate + interval '1 year') as RecentGoldSilverBadges,
    -- Complex case expression with window functions
    case
        when us.TotalPostScore > 1000 and ar.UserReputationRank <= 100 then 'Elite Contributor'
        when us.TotalPostScore between 500 and 1000 and ar.UserReputationRank <= 500 then 'Experienced Contributor'
        when us.TotalPostScore < 500 then 'Novice'
        else 'Intermediate'
    end as ContributorLevel,
    -- String manipulation and null check combined with expressions
    coalesce(substring(u.AboutMe from 1 for 100), 'No AboutMe info') || 
    ' | Location: ' || coalesce(u.Location, 'Unknown') as UserProfileSummary
from Users u
left join UserStats us on us.UserId = u.Id
left join TopPosts ta on ta.OwnerUserId = u.Id and ta.RowNumByUserScore = 1
left join AcceptedAnswerStats aa on aa.QuestionId = ta.PostId
left join DuplicateQuestions dq on dq.DuplicateQuestionId = ta.PostId
left join QuestionCloseInfo qci on qci.PostId = ta.PostId
left join UserActivityRank ar on ar.UserId = u.Id
where u.Reputation > 1000
  and (ta.Score > 50 or ta.ViewCount > 10000)
  and (qci.CloseVotesCount is null or qci.CloseVotesCount = 0)
order by u.Reputation desc nulls last, us.TotalPostScore desc nulls last
limit 100;