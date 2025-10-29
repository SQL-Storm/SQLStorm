-- {"query": "2293.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1368} 
with RecursiveTagTree as (
    select
        t.Id,
        t.TagName,
        array[t.TagName] as TagPath,
        1 as Depth
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        parent.TagPath || child.TagName,
        parent.Depth + 1
    from Tags child
    join RecursiveTagTree parent on child.WikiPostId = parent.Id
    where child.Id != parent.Id and not child.TagName = any(parent.TagPath)
),
UserPostsWithMetrics as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.CreationDate,
        rank() over (partition by u.Id order by p.Score desc NULLS LAST, p.ViewCount desc NULLS LAST) as PostRank,
        count(*) over (partition by u.Id) as TotalPosts,
        sum(p.Score) over (partition by u.Id) as SumScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) -- Questions and Answers
),
AcceptedAnswerStats as (
    select
        p.AcceptedAnswerId,
        count(*) as NumQuestionsAccepted,
        avg(p.Score) as AvgQuestionScore,
        max(p.ViewCount) as MaxQuestionViews
    from Posts p
    where p.AcceptedAnswerId is not null
    group by p.AcceptedAnswerId
),
ComplexUserBadgeAggregation as (
    select
        b.UserId,
        u.DisplayName,
        string_agg(distinct case when b.Class = 1 then b.Name end, ', ') filter (where b.Class = 1) as GoldBadges,
        string_agg(distinct case when b.Class = 2 then b.Name end, ', ') filter (where b.Class = 2) as SilverBadges,
        string_agg(distinct case when b.Class = 3 then b.Name end, ', ') filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Id) as TotalBadges,
        bool_or(b.TagBased) as HasTagBased,
        max(b.Date) as LastBadgeDate,
        count(distinct case when date_part('year', age(current_date, b.Date)) <= 1 then b.Id end) as BadgesLastYear
    from Badges b
    join Users u on u.Id = b.UserId
    group by b.UserId, u.DisplayName
)
select
    u.DisplayName,
    coalesce(upwm.TotalPosts, 0) as TotalPosts,
    coalesce(upwm.SumScore, 0) as TotalScore,
    coalesce(badges.TotalBadges, 0) as BadgeCount,
    badges.GoldBadges,
    badges.SilverBadges,
    badges.BronzeBadges,
    badges.HasTagBased,
    badges.LastBadgeDate,
    badges.BadgesLastYear,
    aa.NumQuestionsAccepted,
    aa.AvgQuestionScore,
    aa.MaxQuestionViews,
    rtt.Depth as TagDepthSample,
    rtt.TagPath as SampleTagPath,
    substring(upwm.Tags for 100) as SampleTags,
    -- calculate a complicated expression involving string length and score normalization
    case
        when upwm.SumScore > 0 then round( ln(abs(upwm.SumScore) + 1) * length(coalesce(upwm.Tags, ''))::float / nullif(upwm.TotalPosts,0), 3)
        else null
    end as ScoreTagMetric,
    -- outer join aggregate number of comments per user, counting distinct Posts commented on
    coalesce(comm.PostsCommentedOn, 0) as PostsCommentedOnCount,
    coalesce(comm.CommentsCount, 0) as TotalCommentsMade,
    -- complex NULL logic: last active days, fallback to creation date if LastAccessDate null
    extract(day from now() - coalesce(u.LastAccessDate, u.CreationDate)) as DaysSinceLastAccess,
    -- correlated subquery: fetch most recent high-scoring question title of user
    (
        select p2.Title
        from Posts p2
        where p2.OwnerUserId = u.Id
          and p2.PostTypeId = 1
          and p2.Score >= 50
        order by p2.CreationDate desc nulls last
        limit 1
    ) as TopQuestionTitle,
    -- use union all and distinct in a lateral join for multi metric user interactions
    interactions.InteractionCount,
    interactions.TopInteractionType
from Users u
left join UserPostsWithMetrics upwm on upwm.UserId = u.Id and upwm.PostRank = 1
left join ComplexUserBadgeAggregation badges on badges.UserId = u.Id
left join AcceptedAnswerStats aa on aa.AcceptedAnswerId = upwm.PostId
left join RecursiveTagTree rtt on rtt.Id = (
    select coalesce(
        (select p3.Id from Posts p3 where p3.OwnerUserId = u.Id and p3.PostTypeId = 1 order by p3.CreationDate desc limit 1),
        (select min(Id) from Tags where IsRequired = 1)
    )
)
left join (
    select
        c.UserId,
        count(distinct c.PostId) as PostsCommentedOn,
        count(c.Id) as CommentsCount
    from Comments c
    group by c.UserId
) comm on comm.UserId = u.Id
left join lateral (
    select
        sum(cnt) as InteractionCount,
        max(InteractionType) as TopInteractionType
    from (
        select 'Votes' as InteractionType, count(*) as cnt
        from Votes v
        where v.UserId = u.Id
        union all
        select 'Comments' as InteractionType, count(*)
        from Comments c2
        where c2.UserId = u.Id
        union all
        select 'Badges' as InteractionType, count(*)
        from Badges b2
        where b2.UserId = u.Id
    ) interaction_counts
) interactions on true
where u.Reputation > 1000
order by TotalScore desc nulls last, TotalPosts desc nulls last
limit 50;