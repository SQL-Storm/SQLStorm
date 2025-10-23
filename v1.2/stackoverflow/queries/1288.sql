-- {"query": "1288.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2181} 
with recursive RecursiveTags as (
    select
        Id,
        TagName,
        Count,
        ExcerptPostId,
        WikiPostId,
        IsModeratorOnly,
        IsRequired,
        1 as Level,
        array[Id] as Path
    from Tags
    where Id in (
        select distinct unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))::int
        from Posts p where p.PostTypeId = 1 and p.Tags is not null
        limit 100
    )
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTags r
        on t.Id <> all(r.Path)
    where t.Id in (
        select distinct unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))::int
        from Posts p where p.PostTypeId = 1 and p.Tags is not null
    ) and array_length(r.Path, 1) < 3
),
UserBadgeStats as (
    select
        b.UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount,
        max(b.Date) as LastBadgeDate
    from Badges b
    join Users u on u.Id = b.UserId
    where b.Class in (1,2,3)
    group by b.UserId, u.DisplayName, b.Class
),
UserPostsFiltered as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
      and p.Score >= 5
      and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
AnswerWithQuestion as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        a.OwnerUserId,
        a.CreationDate as AnswerCreationDate
    from Posts a
    left join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
),
TopScoringAnswers as (
    select
        AnswerId,
        QuestionId,
        AnswerScore,
        QuestionTitle,
        QuestionTags,
        OwnerUserId,
        AnswerCreationDate,
        rank() over (partition by QuestionId order by AnswerScore desc, AnswerCreationDate) as AnswerRank
    from AnswerWithQuestion
),
FilteredTopAnswers as (
    select *
    from TopScoringAnswers
    where AnswerRank <= 3
),
PostLinkInfo as (
    select
        pl.Id as LinkId,
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p.Score as RelatedPostScore,
        p.PostTypeId as RelatedPostType
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p on p.Id = pl.RelatedPostId
),
UserActivityFlags as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1 and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '6 months') as RecentQuestions,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2 and p2.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '6 months') as RecentAnswers,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10 and ph.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '6 months') as RecentClosures,
        bool_or(ph.PostHistoryTypeId = 11) as HasReopenedPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
),
UserBadgesSummary as (
    select
        UserId,
        max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadgeStats
    group by UserId
),
ComplexUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.RecentQuestions,
        ua.RecentAnswers,
        ua.RecentClosures,
        ua.HasReopenedPosts,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc nulls last) as RepRank,
        case
            when u.Location is null or length(trim(u.Location)) = 0 then 'Unknown'
            else substring(u.Location from '([^,]+)')
        end as PartialLocation,
        -- Calculate activity score weighting recent questions and answers and badges
        ((coalesce(ua.RecentQuestions,0) * 2) + (coalesce(ua.RecentAnswers,0) * 3) + (coalesce(ubs.GoldBadges,0) * 5) 
          + (coalesce(ubs.SilverBadges,0) * 2) + (coalesce(ubs.BronzeBadges,0)) 
          - (coalesce(ua.RecentClosures,0) * 4)) as ActivityScore
    from Users u
    left join UserActivityFlags ua on ua.UserId = u.Id
    left join UserBadgesSummary ubs on ubs.UserId = u.Id
),
MostCommentedClosedQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.ClosedDate,
        p.CommentCount,
        rank() over (order by p.CommentCount desc, p.ClosedDate asc nulls last) as RankByComments
    from Posts p
    where p.PostTypeId = 1 and p.ClosedDate is not null and p.CommentCount > 0
),
CorrelatedVotesAnalysis as (
    select
        p.Id as PostId,
        p.Score,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        greatest(0, (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) - (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3)) as NetPositiveVotes,
        case
            when p.ViewCount = 0 or p.ViewCount is null then null
            else round(((select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2)::numeric / p.ViewCount) * 100, 2)
        end as UpVotePercentage,
        left(p.Title || ' | ' || coalesce((select Name from PostTypes pt where pt.Id = p.PostTypeId), 'Unknown'), 100) as CompositeTitle
    from Posts p
    where p.Score >= 10 and p.PostTypeId in (1,2)
),
SetComparison as (
    select u1.UserId, u1.GoldBadges, u2.UserId as OtherUserId, u2.GoldBadges as OtherGoldBadges
    from UserBadgesSummary u1
    join UserBadgesSummary u2 on u1.GoldBadges > 0 and u2.GoldBadges > 0 and u1.UserId <> u2.UserId
    where u1.GoldBadges > u2.GoldBadges
    limit 100
)
select 
    cs.UserId,
    cu.DisplayName,
    cs.GoldBadges,
    cs.OtherUserId,
    ou.DisplayName as OtherDisplayName,
    cs.OtherGoldBadges,
    concat('User ', cu.DisplayName, ' has ', cs.GoldBadges, 
        ' gold badges, more than user ', ou.DisplayName, ' who has ', cs.OtherGoldBadges, ' gold badges.') as ComparisonText,
    csa.PostId,
    csa.CompositeTitle,
    csa.Score,
    csa.UpVotes,
    csa.DownVotes,
    csa.NetPositiveVotes,
    csa.UpVotePercentage,
    mu.PartialLocation,
    mu.ActivityScore,
    mu.Reputation,
    mu.RepRank,
    mtq.Title as MostCommentedClosedQuestionTitle,
    mtq.CommentCount,
    mtq.ClosedDate
from SetComparison cs
join ComplexUserStats cu on cu.Id = cs.UserId
join ComplexUserStats ou on ou.Id = cs.OtherUserId
left join CorrelatedVotesAnalysis csa on csa.PostId = (
    select p.Id
    from Posts p
    where p.OwnerUserId = cs.UserId and p.Score = (
        select max(Score) 
        from Posts p2 
        where p2.OwnerUserId = cs.UserId and p2.PostTypeId in (1,2)
    )
    limit 1
)
left join ComplexUserStats mu on mu.Id = cs.UserId
left join MostCommentedClosedQuestions mtq on mtq.RankByComments = 1
order by cs.GoldBadges desc, cs.OtherGoldBadges asc
limit 50;