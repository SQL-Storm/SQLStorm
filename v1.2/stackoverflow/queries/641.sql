-- {"query": "641.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1468} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
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
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
        case when p.Score > 0 then 'Positive'
             when p.Score = 0 then 'Neutral'
             else 'Negative' end as ScoreCategory,
        coalesce(p.FavoriteCount, 0) * 1.0 / nullif(p.ViewCount,0) as FavToViewRatio
    from Posts p
    where p.PostTypeId = 1
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
UserActivitySummary as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast,
        coalesce(sum(v.BountyAmount), 0) as BountyGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopScoringAnswers as (
    select 
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
AcceptedAnswerInfo as (
    select
        q.Id as QuestionId,
        q.Title,
        a.Id as AcceptedAnswerId,
        a.OwnerUserId as AcceptedUserId,
        a.Score as AcceptedAnswerScore
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate as UserCreated,
    coalesce(ub.GoldBadges, 0) as GoldBadges,
    coalesce(ub.SilverBadges, 0) as SilverBadges,
    coalesce(ub.BronzeBadges, 0) as BronzeBadges,
    coalesce(ua.QuestionsAsked, 0) as QuestionsAsked,
    coalesce(ua.AnswersGiven, 0) as AnswersGiven,
    coalesce(ua.CommentsMade, 0) as CommentsMade,
    coalesce(ua.UpVotesCast, 0) as UpVotesCast,
    coalesce(ua.DownVotesCast, 0) as DownVotesCast,
    coalesce(ua.BountyGiven, 0) as BountyGiven,
    pt.Title as RecentPostTitle,
    pt.Score as RecentPostScore,
    pt.ScoreCategory as RecentPostScoreCategory,
    pt.FavToViewRatio as RecentPostFavToViewRatio,
    dt.TagName as TopTagName,
    dt.Count as TopTagCount,
    dt.TotalAnswers as TopTagTotalAnswers,
    dt.TagRank as TopTagRank,
    ca.CloseReason,
    ca.CloseDate,
    ca.ClosedByUserName,
    da.PostTitle as DuplicatePostTitle,
    da.RelatedPostTitle as DuplicateOfTitle,
    aa.Title as AcceptedQuestionTitle,
    aa.AcceptedAnswerScore,
    aa.AcceptedUserId
from Users u
left join UserBadgeSummary ub on ub.UserId = u.Id
left join UserActivitySummary ua on ua.Id = u.Id
left join PostActivityWindow pt on pt.OwnerUserId = u.Id and pt.RecentPostRank = 1
left join RecursiveTagCounts dt on dt.TagRank = 1
left join ClosedQuestions ca on ca.ClosedByUserId = u.Id
left join DuplicateLinks da on da.PostId = pt.Id
left join AcceptedAnswerInfo aa on aa.AcceptedUserId = u.Id
where u.Reputation > 1000
  and (pt.Score > 10 or pt.FavToViewRatio > 0.01)
  and (ca.CloseDate is null or ca.CloseDate > u.CreationDate)
order by u.Reputation desc, pt.Score desc
limit 100;