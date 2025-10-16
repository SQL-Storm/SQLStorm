-- {"query": "134.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2161} 
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
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
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
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
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
        min(u.CreationDate) as UserSince
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9) -- BountyStart and BountyClose
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreDenseRank
    from Posts p
    where p.PostTypeId in (1,2)
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwner,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AcceptedAnswerUpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AcceptedAnswerDownVotes
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
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
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased = 1) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
TopUsersWithBadges as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        ua.LastPostDate,
        ua.UserSince,
        coalesce(ubs.TotalBadges,0) as TotalBadges,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.HasTagBasedBadge,false) as HasTagBasedBadge
    from UserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
    where ua.Reputation > 10000
),
RecentPostEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        p.Title,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRank
    from PostHistory ph
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
FilteredRecentEdits as (
    select
        rpe.PostId,
        rpe.Title,
        rpe.CreationDate,
        rpe.UserId,
        rpe.UserDisplayName,
        rpe.Comment
    from RecentPostEdits rpe
    where rpe.EditRank = 1
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        count(a.Id) as ActualAnswerCount,
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
        max(a.Score) filter (where a.Score is not null) as MaxAnswerScore,
        min(a.Score) filter (where a.Score is not null) as MinAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount
),
ComplexUserPostAnalysis as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as Questions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as Answers,
        sum(p.Score) as TotalPostScore,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCast,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as ReopenVotesCast,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id and ph.PostHistoryTypeId in (10,11)
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (2,3)
    group by u.Id, u.DisplayName
)
select
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionsAsked,
    tu.AnswersGiven,
    tu.CommentsMade,
    tu.TotalBountyGiven,
    tu.LastPostDate,
    tu.UserSince,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.HasTagBasedBadge,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.TotalPostScore,
    ca.AvgPostScore,
    ca.MaxPostScore,
    ca.MinPostScore,
    ca.CloseVotesCast,
    ca.ReopenVotesCast,
    ca.UpVotesCast,
    ca.DownVotesCast,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.AnswerCount,
    qas.ActualAnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    aas.AcceptedAnswerScore,
    aas.AcceptedAnswerUpVotes,
    aas.AcceptedAnswerDownVotes,
    pls.LinkedCount,
    pls.DuplicateCount,
    fre.CreationDate as LastEditDate,
    fre.UserDisplayName as LastEditor,
    fre.Comment as LastEditComment,
    rth.Level as TagHierarchyLevel,
    rth.Path as TagHierarchyPath
from TopUsersWithBadges tu
left join ComplexUserPostAnalysis ca on ca.UserId = tu.UserId
left join QuestionAnswerStats qas on qas.OwnerUserId = tu.UserId
left join AcceptedAnswerStats aas on aas.QuestionOwner = tu.UserId
left join PostLinkSummary pls on pls.PostId = qas.QuestionId
left join FilteredRecentEdits fre on fre.PostId = qas.QuestionId
left join RecursiveTagHierarchy rth on rth.TagName = substring(qas.Title from '[^\s]+') -- crude tag extraction from title
where tu.TotalBadges > 5
  and (qas.QuestionScore > 10 or qas.AnswerCount > 5)
  and (fre.CreationDate is null or fre.CreationDate > tu.UserSince)
order by tu.Reputation desc, qas.QuestionScore desc
limit 100;