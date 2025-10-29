with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.Tags,
        coalesce(p.Title, '') as Title,
        p.AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.Score desc, p.ViewCount desc) as UserPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where p.Id is not null
),
TopPosts as (
    select * from RecursiveUserPosts
    where UserPostRank <= 5
),
PostVotes as (
    select
        v.PostId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
        sum(case when vt.Id in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostCommentsAgg as (
    select
        c.PostId,
        count(*) as TotalComments,
        avg(c.Score) as AvgCommentScore,
        count(distinct c.UserId) as UniqueCommenters,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
PostCloseDetails as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId 
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where pht.Name = 'Post Closed'
),
UserBadgeSummary as (
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
PostLinkSummary as (
    select
        pl.PostId,
        count(case when lt.Name = 'Linked' then 1 end) as LinkedPostsCount,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicatePostsCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
RankedAnswers as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as AnswerRankByScore,
        count(*) over (partition by a.ParentId) as TotalAnswers,
        u.Id as AnswererId,
        u.DisplayName as AnswererName
    from Posts a 
    join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserReputationAge as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        extract(epoch from (timestamp '2024-10-01 12:34:56' - u.CreationDate))/86400 as DaysSinceCreation,
        case when u.Reputation > 0 then u.Reputation / nullif(extract(epoch from (timestamp '2024-10-01 12:34:56' - u.CreationDate))/86400, 0) else 0 end as ReputationPerDay
    from Users u
),
DuplicateQuestions as (
    select distinct pl.PostId as QuestionId, pl.RelatedPostId as DuplicateOfQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
FilteredQuestions as (
    select 
        p.Id,
        coalesce(p.Title, '') as Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId,
        dq.DuplicateOfQuestionId,
        ph.CloseDate,
        ph.CloseReason
    from Posts p
    left join DuplicateQuestions dq on dq.QuestionId = p.Id
    left join PostCloseDetails ph on ph.PostId = p.Id
    where p.PostTypeId = 1
      and p.CreationDate > (timestamp '2024-10-01 12:34:56') - interval '365 days'
)
select
    u.Id as UserId,
    u.DisplayName,
    urs.ReputationPerDay,
    u.CreationDate as UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tp.PostId,
    tp.Title as PostTitle,
    tp.PostCreationDate,
    tp.PostScore,
    tp.ViewCount,
    coalesce(pv.UpVotes, 0) as PostUpVotes,
    coalesce(pv.DownVotes, 0) as PostDownVotes,
    coalesce(pv.TotalBounty, 0) as PostTotalBounty,
    pca.TotalComments,
    coalesce(pca.AvgCommentScore, 0) as AvgCommentScore,
    coalesce(pca.UniqueCommenters, 0) as UniqueCommenters,
    pls.LinkedPostsCount,
    pls.DuplicatePostsCount,
    pq.Id as QuestionId,
    pq.Title as QuestionTitle,
    pq.AnswerCount,
    pq.DuplicateOfQuestionId,
    pq.CloseDate,
    pq.CloseReason,
    ra.AnswerId,
    ra.AnswerCreationDate,
    ra.AnswerScore,
    ra.AnswerRankByScore,
    ra.TotalAnswers,
    ra.AnswererId,
    ra.AnswererName
from Users u
left join UserReputationAge urs on urs.UserId = u.Id
left join UserBadgeSummary bs on bs.UserId = u.Id
left join TopPosts tp on tp.UserId = u.Id
left join PostVotes pv on pv.PostId = tp.PostId
left join PostCommentsAgg pca on pca.PostId = tp.PostId
left join PostLinkSummary pls on pls.PostId = tp.PostId
left join FilteredQuestions pq on pq.Id = tp.PostId and tp.PostTypeId = 1
left join RankedAnswers ra on ra.QuestionId = pq.Id
where u.Reputation > 1000 
  and (
    (tp.PostTypeId = 1 and tp.PostScore > 10 and tp.ViewCount > 1000)
    or 
    (tp.PostTypeId = 2 and tp.PostScore > 5)
  )
order by urs.ReputationPerDay desc, u.Reputation desc, tp.PostScore desc
limit 100;