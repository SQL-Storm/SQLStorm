-- {"query": "438.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1395} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, 1 as Level
    from Tags t
    where t.Count > 1000
    union all
    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, t2.IsModeratorOnly, t2.IsRequired, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id - 1 and r.Level < 3
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank,
        dense_rank() over (partition by u.Location order by u.Reputation desc) as LocationReputationRank
    from Users u
    where u.Reputation > 1000
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score), 0) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        count(distinct c.Id) as CommentCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    left join Comments c on c.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.Score > 0 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PositiveScorePostsLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 500
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
HighScoringPosts as (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    where p.Score > 50 and p.PostTypeId in (1,2)
),
UserBadgeSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select 
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.AnswerCount,
    qas.TotalAnswerScore,
    qas.MaxAnswerScore,
    qas.CloseVotesCount,
    qas.CommentCount,
    ur.Reputation,
    ur.ReputationRank,
    ur.LocationReputationRank,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ua.PostsLast30Days,
    ua.PositiveScorePostsLast30Days,
    dt.TagName as PopularTag,
    hlp.Title as HighScorePostTitle,
    hlp.Score as HighScorePostScore,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    case 
        when qas.CloseVotesCount > 5 then 'Likely to be Closed'
        when qas.AnswerCount = 0 then 'Unanswered'
        when qas.MaxAnswerScore > 10 then 'Highly Answered'
        else 'Normal'
    end as QuestionStatus,
    case 
        when ur.LocationReputationRank = 1 then 'Top in Location'
        else 'Normal User'
    end as UserLocationRankStatus,
    concat_ws(' | ', 
        coalesce(qas.Title, ''), 
        coalesce(ur.DisplayName, ''), 
        coalesce(dt.TagName, ''), 
        coalesce(ubs.GoldBadges::text, '0'), 
        coalesce(hlp.Score::text, '0')
    ) as CompositeString
from QuestionAnswerStats qas
left join Users ur on ur.Id = qas.OwnerUserId
left join UserBadgeSummary ubs on ubs.UserId = ur.Id
left join UserActivityWindow ua on ua.UserId = ur.Id
left join RecursiveTagHierarchy dt on dt.Level = 1 and dt.TagName = substring(qas.Title from '%#"%#"%' for '#')
left join HighScoringPosts hlp on hlp.PostTypeId = 2 and hlp.ScoreRank = 1
left join DuplicateLinks dup on dup.PostId = qas.QuestionId
where qas.AnswerCount > 0
  and (ur.ReputationRank <= 100 or ur.LocationReputationRank <= 5)
order by qas.TotalAnswerScore desc, ur.Reputation desc
limit 100;