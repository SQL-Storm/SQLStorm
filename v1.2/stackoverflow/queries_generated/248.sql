-- {"query": "248.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1483} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (order by t.Count desc) as RankByCount
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerName,
        pt.Name as PostTypeName
    from PostLinks pl
    inner join Posts p on p.Id = pl.PostId
    inner join Users u on u.Id = p.OwnerUserId
    inner join PostTypes pt on pt.Id = p.PostTypeId
    where pl.LinkTypeId = 3
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    inner join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopActiveUsers as (
    select
        uas.Id,
        uas.DisplayName,
        uas.QuestionsAsked,
        uas.AnswersGiven,
        uas.CommentsMade,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        uas.LastPostDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.TagBasedBadges
    from UserActivitySummary uas
    left join UserBadgeSummary ubs on ubs.UserId = uas.Id
    where uas.QuestionsAsked + uas.AnswersGiven + uas.CommentsMade > 100
    order by (uas.QuestionsAsked + uas.AnswersGiven + uas.CommentsMade) desc
    limit 10
)
select
    t.Id as TagId,
    t.TagName,
    t.Count as TagCount,
    t.TotalAnswers,
    t.TotalViews,
    t.RankByCount,
    du.PostId as DuplicatePostId,
    du.RelatedPostId as DuplicateOfPostId,
    du.OwnerName as DuplicatePostOwner,
    du.PostTypeName as DuplicatePostType,
    cq.ClosedDate,
    cq.CloseReason,
    cq.Title as ClosedQuestionTitle,
    ta.DisplayName as TopUserDisplayName,
    ta.QuestionsAsked,
    ta.AnswersGiven,
    ta.CommentsMade,
    ta.GoldBadges,
    ta.SilverBadges,
    ta.BronzeBadges,
    ta.TagBasedBadges,
    paw.Id as PostId,
    paw.PostTypeId,
    paw.Score as PostScore,
    paw.ViewCount as PostViewCount,
    paw.CommentCount as PostCommentCount,
    paw.UpVotes as PostUpVotes,
    paw.DownVotes as PostDownVotes,
    paw.Title as PostTitle,
    paw.Tags as PostTags,
    paw.PrevScore,
    paw.NextScore
from RecursiveTagCounts t
left join DuplicateLinks du on du.PostId = (
    select p.Id from Posts p
    where p.Tags like concat('%<', t.TagName, '>%')
    order by p.Score desc limit 1
)
left join ClosedQuestions cq on cq.PostId = du.PostId
left join TopActiveUsers ta on ta.Id = cq.OwnerUserId
left join PostActivityWindow paw on paw.OwnerUserId = ta.Id and paw.RecentPostRank = 1
where t.Count > 1000
union
select
    t.Id,
    t.TagName,
    t.Count,
    t.TotalAnswers,
    t.TotalViews,
    t.RankByCount,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null
from RecursiveTagCounts t
where t.Count <= 1000
order by RankByCount, TagName;