with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVoteSummary as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as Favorites,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p1 on p1.Id = pl.PostId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Linked', 'Duplicate')
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnswersWithOwner,
        sum(case when a.AcceptedAnswerId = a.Id then 1 else 0 end) as AcceptedAnswersCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes cht on cht.Id = ph.PostHistoryTypeId
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
TopQuestionsWithBadges as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        row_number() over (order by q.Score desc, q.ViewCount desc) as Rank
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeStats ub on ub.UserId = u.Id
    where q.PostTypeId = 1
    and q.Score > 10
)
select
    tq.Rank,
    tq.QuestionId,
    tq.Title,
    tq.Score as QuestionScore,
    tq.ViewCount as QuestionViews,
    tq.OwnerName,
    tq.OwnerReputation,
    tq.GoldBadges,
    tq.SilverBadges,
    tq.BronzeBadges,
    qa.AnswerCount,
    qa.MaxAnswerScore,
    qa.AvgAnswerScore,
    coalesce(cr.CloseCount, 0) as CloseVotes,
    pvs.UpVotes as TotalUpVotes,
    pvs.DownVotes as TotalDownVotes,
    pvs.Favorites as TotalFavorites,
    pvs.TotalBounty,
    string_agg(distinct (pl.LinkTypeName || ':' || cast(pl.RelatedPostId as varchar)), ', ') as RelatedLinks,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.Reputation,
    ua.LastAccessDate
from TopQuestionsWithBadges tq
left join QuestionAnswerStats qa on qa.QuestionId = tq.QuestionId
left join CloseReasonCounts cr on cr.CloseReason = 'Duplicate'
left join PostVoteSummary pvs on pvs.PostId = tq.QuestionId
left join PostLinkDetails pl on pl.PostId = tq.QuestionId
left join UserActivityWindow ua on ua.UserId = (
    select OwnerUserId from Posts where Id = tq.QuestionId
)
group by
    tq.Rank,
    tq.QuestionId,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.OwnerName,
    tq.OwnerReputation,
    tq.GoldBadges,
    tq.SilverBadges,
    tq.BronzeBadges,
    qa.AnswerCount,
    qa.MaxAnswerScore,
    qa.AvgAnswerScore,
    cr.CloseCount,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.Favorites,
    pvs.TotalBounty,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.Reputation,
    ua.LastAccessDate
order by tq.Rank
limit 50;