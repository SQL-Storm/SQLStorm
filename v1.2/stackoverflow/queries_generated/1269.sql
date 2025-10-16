-- {"query": "1269.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1070} 
with RecursiveUserScores as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(count(b.Id), 0) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.Id) as Rnk
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopScoringPosts as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2) and p.Score > 5
),
PostWithAcceptedAnswer as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        a.Id as AcceptedAnswerId,
        a.OwnerUserId as AcceptedAnswerOwnerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerDate,
        p.ViewCount
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Posts p on p.Id = q.Id
    where q.PostTypeId = 1
),
FilteredComments as (
    select
        c.PostId,
        c.UserId,
        c.Score,
        c.Text,
        row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate desc) as CommentRank
    from Comments c
    where c.Score is not null and c.Score > 2
),
AggregatedVotes as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount, 0) else 0 end) as TotalBounty
    from Votes v
    group by v.PostId
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name,
        b.Class,
        rank() over (partition by b.UserId order by b.Date desc) as RecentBadgeRank
    from Badges b
),
DuplicatePostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p.Title as OriginalTitle,
        rp.Title as DuplicateOfTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p on p.Id = pl.PostId
    join Posts rp on rp.Id = pl.RelatedPostId
),
ClosedQuestionsAS Is (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstClosedDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
)
select distinct
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPostScore,
    ru.BadgeCount,
    tsp.Title as TopPostTitle,
    tsp.Score as TopPostScore,
    coalesce(aw.UpVotes, 0) as PostUpVotes,
    coalesce(aw.DownVotes, 0) as PostDownVotes,
    coalesce(aw.TotalBounty, 0) as PostBounty,
    pwa.AcceptedAnswerId,
    pwa.AcceptedAnswerScore,
    coalesce(cq.FirstClosedDate, null) as ClosedDate,
    clpl.DuplicateOfTitle as DuplicateOf,
    fc.Text as TopCommentText,
    ub.Name as RecentBadgeName,
    ub.Class as RecentBadgeClass
from RecursiveUserScores ru
left join TopScoringPosts tsp on tsp.OwnerUserId = ru.UserId and tsp.ScoreRank = 1
left join AggregatedVotes aw on aw.PostId = tsp.Id
left join PostWithAcceptedAnswer pwa on pwa.QuestionId = tsp.Id
left join FilteredComments fc on fc.PostId = tsp.Id and fc.CommentRank = 1
left join UserBadgeRanks ub on ub.UserId = ru.UserId and ub.RecentBadgeRank = 1
left join ClosedQuestionsAS cq on cq.PostId = tsp.Id
left join DuplicatePostLinks clpl on clpl.PostId = tsp.Id
where ru.Rnk <= 100
order by ru.Reputation desc, ru.TotalPostScore desc
limit 50;