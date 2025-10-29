-- {"query": "2729.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1619} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(sum(vt2.UpVotes),0) as TotalAnswerUpVotes,
        row_number() over (partition by u.Id order by max(p.LastActivityDate) desc nulls last) as LastActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id and p2.PostTypeId = 2
    left join (
        select
            p.OwnerUserId,
            count(v.Id) as UpVotes
        from Votes v
        join Posts p on p.Id = v.PostId
        where v.VoteTypeId = 2
        group by p.OwnerUserId
    ) vt2 on vt2.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
BadgeAggregation as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserTopPosts as (
    select
        p.OwnerUserId as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as PostRank
    from Posts p
    where p.OwnerUserId is not null
),
ClosedQuestions as (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstClosedDate,
        array_agg(distinct crt.Name) filter (where crt.Name is not null) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
AnswerStatistics as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        count(a.Id) as AnswerCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnswersWithOwners,
        count(distinct v.UserId) as DistinctVotersOnAnswers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = a.Id and v.VoteTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate
),
TagSplit as (
    select
        q.Id as QuestionId,
        unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
),
TopTags as (
    select
        ts.TagName,
        count(distinct ts.QuestionId) as QuestionCount,
        avg(ans.AnswerCount) as AvgAnswerCount,
        avg(ans.AvgAnswerScore) as AvgAnswerScore
    from TagSplit ts
    join AnswerStatistics ans on ans.QuestionId = ts.QuestionId
    group by ts.TagName
    having count(distinct ts.QuestionId) > 10
),
UserActivityWindow as (
    select
        rau.UserId,
        rau.DisplayName,
        rau.Reputation,
        rau.QuestionCount,
        rau.AnswerCount,
        rau.TotalPostScore,
        rank() over (order by rau.Reputation desc) as ReputationRank,
        rank() over (order by rau.TotalPostScore desc) as PostScoreRank,
        rank() over (order by rau.QuestionCount desc) as QuestionRank,
        rank() over (order by rau.AnswerCount desc) as AnswerRank
    from RecursiveUserActivity rau
),
ConsolidatedUserStats as (
    select
        uaw.*,
        coalesce(ba.TotalBadges,0) as TotalBadges,
        coalesce(ba.GoldBadges,0) as GoldBadges,
        coalesce(ba.SilverBadges,0) as SilverBadges,
        coalesce(ba.BronzeBadges,0) as BronzeBadges,
        ba.LastBadgeDate
    from UserActivityWindow uaw
    left join BadgeAggregation ba on ba.UserId = uaw.UserId
),
TopUserPostsFinal as (
    select
        utp.UserId,
        utp.PostId,
        pt.Name as PostTypeName,
        utp.Score,
        utp.ViewCount,
        utp.CreationDate,
        dense_rank() over (partition by utp.UserId order by utp.Score desc nulls last, utp.ViewCount desc nulls last) as Ranking
    from UserTopPosts utp
    left join PostTypes pt on pt.Id = utp.PostTypeId
    where utp.PostRank <= 5
)
select
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.QuestionCount,
    cus.AnswerCount,
    cus.TotalPostScore,
    cus.TotalBadges,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.LastBadgeDate,
    tp.PostId as TopPostId,
    tp.PostTypeName,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViews,
    tp.CreationDate as TopPostCreationDate,
    coalesce(clq.FirstClosedDate, null) as FirstClosedDate,
    coalesce(array_to_string(clq.CloseReasons, ', '), 'No Close Reason') as CloseReasons,
    ttag.TagName as PopularTag,
    ttag.QuestionCount as TagQuestionCount,
    ttag.AvgAnswerCount as TagAvgAnswerCount,
    ttag.AvgAnswerScore as TagAvgAnswerScore
from ConsolidatedUserStats cus
left join TopUserPostsFinal tp on tp.UserId = cus.UserId and tp.Ranking = 1
left join Posts pq on pq.OwnerUserId = cus.UserId and pq.PostTypeId = 1
left join ClosedQuestions clq on clq.PostId = pq.Id
left join TagSplit ts on ts.QuestionId = pq.Id
left join TopTags ttag on ttag.TagName = ts.TagName
where cus.Reputation > (
    select avg(Reputation) from Users where Reputation > 100
)
and (
    tp.Score > 10 or tp.Score is null
)
and (
    clq.FirstClosedDate is null or clq.FirstClosedDate > cast('2024-10-01' as date) - interval '1 year'
)
order by cus.Reputation desc nulls last, tp.Score desc nulls last, cus.TotalBadges desc nulls last
limit 100;