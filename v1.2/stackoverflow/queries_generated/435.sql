-- {"query": "435.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2058} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Ancestors
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Ancestors || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Ancestors)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
UserBadgeStats as (
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
PostScoreRanked as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as ScoreRank,
        rank() over (partition by p.OwnerUserId order by p.CreationDate) as CreationRank
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(sum(p.ViewCount), 0) as TotalPostViews,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopPostsWithComments as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        c.CommentCount,
        coalesce(c.MaxCommentScore, 0) as MaxCommentScore,
        coalesce(c.AvgCommentScore, 0) as AvgCommentScore,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        p.Tags
    from Posts p
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(Score) as MaxCommentScore,
            avg(Score::float) as AvgCommentScore
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId = 1 and p.Score > 5
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(*) filter (where lt.Name = 'Linked') as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
UserRecentActivity as (
    select
        ph.UserId,
        max(ph.CreationDate) as LastEditDate,
        count(*) as EditCount,
        count(distinct ph.PostId) as EditedPostsCount,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount
    from PostHistory ph
    group by ph.UserId
),
AnswerAcceptedStatus as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted
    from Posts a
    join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2
),
UserAnswerStats as (
    select
        a.OwnerUserId,
        count(a.Id) as TotalAnswers,
        sum(coalesce(a.Score,0)) as TotalAnswerScore,
        sum(coalesce(aas.IsAccepted,0)) as AcceptedAnswersCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Posts a
    left join AnswerAcceptedStatus aas on aas.AnswerId = a.Id
    where a.PostTypeId = 2
    group by a.OwnerUserId
),
HighRepUsersWithBadges as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.DistinctBadges,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalPostScore,
        uas.TotalPostViews,
        uas.LastPostDate,
        uas.LastAccessDate,
        uas.Reputation / nullif(date_part('day', now() - u.CreationDate),0) as RepPerDay,
        uas.LastPostDate > now() - interval '30 days' as ActiveLast30Days
    from Users u
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    left join UserActivitySummary uas on uas.UserId = u.Id
    where u.Reputation > 10000
),
RecentTopPostsWithLinks as (
    select
        tpp.PostId,
        tpp.Title,
        tpp.OwnerUserId,
        tpp.CreationDate,
        tpp.Score,
        tpp.ViewCount,
        tpp.CommentCount,
        tpp.MaxCommentScore,
        tpp.AvgCommentScore,
        dl.DuplicateCount,
        dl.LinkedCount,
        tpp.IsClosed,
        tpp.Tags
    from TopPostsWithComments tpp
    left join DuplicateLinkCounts dl on dl.PostId = tpp.PostId
    where tpp.CreationDate > now() - interval '180 days'
),
FinalUserPostStats as (
    select
        hru.Id as UserId,
        hru.DisplayName,
        hru.Reputation,
        hru.GoldBadges,
        hru.SilverBadges,
        hru.BronzeBadges,
        hru.DistinctBadges,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalPostScore,
        uas.TotalPostViews,
        uas.LastPostDate,
        uas.LastAccessDate,
        uas.RepPerDay,
        uas.ActiveLast30Days,
        uas.LastPostDate - u.CreationDate as DaysSinceLastPost,
        uas.LastAccessDate - u.CreationDate as DaysSinceLastAccess,
        coalesce(uas.QuestionCount,0) + coalesce(uas.AnswerCount,0) as TotalPosts,
        coalesce(uas.TotalPostScore,0) / nullif(coalesce(uas.QuestionCount,0) + coalesce(uas.AnswerCount,0),0) as AvgScorePerPost
    from HighRepUsersWithBadges hru
    join Users u on u.Id = hru.Id
    left join UserActivitySummary uas on uas.UserId = hru.Id
)
select
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.DistinctBadges,
    fus.QuestionCount,
    fus.AnswerCount,
    fus.TotalPosts,
    fus.TotalPostScore,
    fus.AvgScorePerPost,
    fus.TotalPostViews,
    fus.LastPostDate,
    fus.LastAccessDate,
    fus.RepPerDay,
    fus.ActiveLast30Days,
    fus.DaysSinceLastPost,
    fus.DaysSinceLastAccess,
    array_agg(distinct tpp.Title order by tpp.Score desc nulls last limit 3) as Top3RecentQuestionTitles,
    array_agg(distinct concat_ws(' | ', tpp.Title, 'Score:', tpp.Score::text, 'Comments:', tpp.CommentCount::text) order by tpp.Score desc nulls last limit 5) as Top5RecentQuestionsSummary
from FinalUserPostStats fus
left join Posts p on p.OwnerUserId = fus.UserId and p.PostTypeId = 1
left join RecentTopPostsWithLinks tpp on tpp.OwnerUserId = fus.UserId
where fus.ActiveLast30Days = true
group by
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.DistinctBadges,
    fus.QuestionCount,
    fus.AnswerCount,
    fus.TotalPosts,
    fus.TotalPostScore,
    fus.AvgScorePerPost,
    fus.TotalPostViews,
    fus.LastPostDate,
    fus.LastAccessDate,
    fus.RepPerDay,
    fus.ActiveLast30Days,
    fus.DaysSinceLastPost,
    fus.DaysSinceLastAccess
order by fus.Reputation desc, fus.GoldBadges desc, fus.TotalPostScore desc
limit 20;