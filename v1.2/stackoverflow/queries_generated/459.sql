-- {"query": "459.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2190} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnswersWithOwner
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(p.PostCount, 0) as PostCount,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(ub.TotalBadges, 0) as TotalBadges,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        case when u.WebsiteUrl is not null and length(trim(u.WebsiteUrl)) > 0 then 1 else 0 end as HasWebsite
    from Users u
    left join (
        select OwnerUserId, count(*) as PostCount
        from Posts
        where OwnerUserId is not null
        group by OwnerUserId
    ) p on p.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        where UserId is not null
        group by UserId
    ) c on c.UserId = u.Id
    left join (
        select UserId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        where UserId is not null
        group by UserId
    ) v on v.UserId = u.Id
    left join UserBadgeStats ub on ub.UserId = u.Id
),
TopQuestionsWithDetails as (
    select
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        pas.AnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.MinAnswerScore,
        pas.AnswersWithOwner,
        row_number() over (order by q.Score desc, q.ViewCount desc) as RankByScoreView
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    left join PostAnswerStats pas on pas.QuestionId = q.Id
    where q.PostTypeId = 1
      and q.Score is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
FilteredComments as (
    select
        c.Id,
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Text,
        length(c.Text) as TextLength,
        case when c.UserId is null then 1 else 0 end as IsAnonymous,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRankDesc
    from Comments c
    where c.Text is not null and length(trim(c.Text)) > 0
),
RecentPostEdits as (
    select
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        ph.Text,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRankDesc
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        rank() over (order by u.Reputation desc) as ReputationRank,
        dense_rank() over (partition by date_part('year', u.CreationDate) order by u.Reputation desc) as YearlyReputationRank
    from Users u
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    inner join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
QuestionsWithBounty as (
    select
        v.PostId,
        max(v.BountyAmount) as MaxBounty,
        count(*) as BountyCount,
        min(v.CreationDate) as FirstBountyDate,
        max(v.CreationDate) as LastBountyDate
    from Votes v
    where v.VoteTypeId in (8,9) -- BountyStart, BountyClose
    group by v.PostId
)
select
    tq.Id as QuestionId,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.CreationDate as QuestionCreated,
    tq.OwnerUserId,
    tq.OwnerName,
    ua.Reputation as OwnerReputation,
    ua.PostCount as OwnerPostCount,
    ua.TotalBadges as OwnerBadgeCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    tq.AnswerCount,
    coalesce(tq.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(tq.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(tq.MinAnswerScore, 0) as MinAnswerScore,
    tq.AnswersWithOwner,
    coalesce(qcb.CloseReason, 'Open') as CloseReason,
    qcb.CloseDate,
    qcb.ClosedByUserName,
    qb.MaxBounty,
    qb.BountyCount,
    qb.FirstBountyDate,
    qb.LastBountyDate,
    dt.DuplicateCount,
    string_agg(distinct dt.DuplicateTitles, ' | ') as DuplicateTitles,
    fc.AnonymousCommentCount,
    fc.TotalCommentCount,
    fc.LatestCommentText,
    rpe.EditCount,
    rpe.LatestEditDate,
    ua.HasWebsite,
    ua.Location,
    ua.DisplayName as OwnerDisplayName,
    ua.EmailHash,
    ua.UpVotes,
    ua.DownVotes,
    ua.Views,
    ua.LastAccessDate,
    ua.CreationDate as UserCreationDate,
    urw.ReputationRank,
    urw.YearlyReputationRank
from TopQuestionsWithDetails tq
left join UserActivity ua on ua.Id = tq.OwnerUserId
left join QuestionsWithCloseReasons qcb on qcb.PostId = tq.Id
left join QuestionsWithBounty qb on qb.PostId = tq.Id
left join (
    select
        pl.PostId,
        count(*) as DuplicateCount,
        string_agg(p.Title, ' || ') as DuplicateTitles
    from PostLinks pl
    join Posts p on p.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
    group by pl.PostId
) dt on dt.PostId = tq.Id
left join (
    select
        c.PostId,
        sum(case when c.IsAnonymous = 1 then 1 else 0 end) as AnonymousCommentCount,
        count(*) as TotalCommentCount,
        max(c.CreationDate) as LatestCommentDate,
        max(c.Text) filter (where c.CommentRankDesc = 1) as LatestCommentText
    from FilteredComments c
    group by c.PostId
) fc on fc.PostId = tq.Id
left join (
    select
        ph.PostId,
        count(*) as EditCount,
        max(ph.CreationDate) as LatestEditDate
    from RecentPostEdits ph
    group by ph.PostId
) rpe on rpe.PostId = tq.Id
left join UserReputationWindow urw on urw.Id = ua.Id
where tq.RankByScoreView <= 100
order by tq.Score desc, tq.ViewCount desc
limit 100;