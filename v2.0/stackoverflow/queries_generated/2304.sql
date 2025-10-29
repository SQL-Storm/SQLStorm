-- {"query": "2304.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1310} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.ViewCount,0) as PostViewCount,
        coalesce(p.Score,0) as PostScore,
        coalesce(p.AnswerCount,0) as AnswerCount,
        u.Reputation as OwnerReputation,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.Tags ilike concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 -- questions only
), TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 5
),
AcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerId,
        u.DisplayName as AcceptedAnswerOwnerName,
        a.CreationDate as AcceptedAnswerCreationDate
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
BadgesSummary as (
    select 
        UserId,
        count(case when Class = 1 then 1 end) as GoldBadges,
        count(case when Class = 2 then 1 end) as SilverBadges,
        count(case when Class = 3 then 1 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges 
    group by UserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        coalesce(SumPosts,0) as TotalPosts,
        coalesce(SumVotes,0) as TotalVotes,
        row_number() over (order by u.Reputation desc) as RankByReputation,
        count(distinct p.Id) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as SumPosts 
        from Posts
        group by OwnerUserId
    ) sp on sp.OwnerUserId = u.Id
    left join (
        select v.UserId, count(*) as SumVotes
        from Votes v
        group by v.UserId
    ) sv on sv.UserId = u.Id
),
ComplexPostStats as (
    select
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        a.AcceptedAnswerScore,
        DENSE_RANK() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRankByOwner,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END as PostStatus,
        concat_ws(' / ', substr(p.Title,1,20), coalesce(u.DisplayName,'<anon>')) as Snippet,
        case when strpos(coalesce(p.Tags,''), '<sql>') > 0 then 1 else 0 end as HasSQLTag,
        (select count(*) from Comments c where c.PostId = p.Id and c.Score >= 5) as CommentCountHighScore,
        coalesce((select sum(v.BountyAmount) from Votes v where v.PostId = p.Id and v.VoteTypeId in (8,9)),0) as BountySum
    from Posts p
    left join AcceptedAnswers a on a.QuestionId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2) -- questions and answers
)
select 
    qpc.TagName,
    qpc.Id as TagId,
    ptp.Id as QuestionId,
    ptp.Title,
    ptp.Score,
    ptp.ViewCount,
    ptp.AnswerCount,
    ptp.OwnerReputation,
    aa.AcceptedAnswerScore,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    uaw.RankByReputation,
    uaw.PostsLast30Days,
    cps.PostStatus,
    cps.Snippet,
    cps.HasSQLTag,
    cps.CommentCountHighScore,
    cps.BountySum
from RecursiveTagCounts qpc
inner join TopTagPosts ptp on ptp.TagId = qpc.TagId and ptp.rn <= 5
left join AcceptedAnswers aa on aa.QuestionId = ptp.Id
left join BadgesSummary ba on ba.UserId = ptp.OwnerUserId
left join UserActivityWindow uaw on uaw.UserId = ptp.OwnerUserId
left join ComplexPostStats cps on cps.PostId = ptp.Id
where qpc.PostViewCount > 1000 
  and (ba.GoldBadges > 0 or ba.SilverBadges > 2)
  and (uaw.PostsLast30Days > 1 or cps.HasSQLTag = 1)
order by qpc.TagName, ptp.Score desc
limit 100
union
select
    null, null, p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount,
    u.Reputation,
    null, 0, 0, 0, null, null, 'Open', substr(p.Title, 1, 20) || ' / ' || coalesce(u.DisplayName,'<anon>'),
    0, 0, 0
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.Score < 0
  and coalesce(p.AnswerCount,0) = 0
order by p.CreationDate desc
limit 10;