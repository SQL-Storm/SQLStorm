-- {"query": "249.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1545} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where r.Level < 3
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
        dense_rank() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyReputationRank
    from Users u
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        count(a.Id) filter (where a.Score > 0) as PositiveAnswerCount,
        count(a.Id) filter (where a.Score <= 0) as NonPositiveAnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
PostWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ClosedDate,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseVoteDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as AnswersGiven,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ' order by c.CreationDate desc) as RecentCommenters
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate
    having count(c.Id) > 5
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
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges,
        count(distinct b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    p.Id as QuestionId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.AcceptedAnswerId,
    p.ClosedDate,
    p.CloseReasonName,
    p.CloseVoteDate,
    pas.PositiveAnswerCount,
    pas.NonPositiveAnswerCount,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.AnonymousAnswerCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.LastAccessDate,
    tc.RecentCommenters,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.RelatedPostTitle as DuplicateOfPostTitle,
    concat_ws(' | ', 
        'Tags: ' || coalesce(p.Tags, 'None'),
        'Owner: ' || coalesce(u.DisplayName, 'Unknown'),
        'Score/View Ratio: ' || round(nullif(p.Score,0)::numeric / nullif(p.ViewCount,1), 4),
        'Badge Summary: G:' || ub.GoldBadges || ' S:' || ub.SilverBadges || ' B:' || ub.BronzeBadges
    ) as SummaryInfo
from PostWithCloseInfo p
left join Users u on u.Id = p.OwnerUserId
left join PostAnswerStats pas on pas.QuestionId = p.Id
left join UserBadgeSummary ub on ub.UserId = p.OwnerUserId
left join UserActivityWindow ua on ua.UserId = p.OwnerUserId and ua.LastPostRank = 1
left join TopPostsWithComments tc on tc.Id = p.Id
left join DuplicateLinks dl on dl.PostId = p.Id
where
    (p.Score > 10 or p.ViewCount > 1000)
    and (p.ClosedDate is null or p.ClosedDate > now() - interval '30 days')
    and (pas.PositiveAnswerCount > 0 or pas.NonPositiveAnswerCount > 5)
order by p.ViewCount desc, p.Score desc
limit 100;