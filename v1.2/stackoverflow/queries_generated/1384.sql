-- {"query": "1384.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1236} 
with RecursiveBadgeCte as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by u.Id order by b.Class, b.Date) rn
    from Users u
    left join Badges b on u.Id = b.UserId and b.TagBased = 0
    where u.Reputation > 1000 
    group by u.Id, u.DisplayName, b.Class
    union all
    select
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount,
        r.rn + 1
    from RecursiveBadgeCte r
    where r.rn < (select max(count(*)) from Badges where TagBased = 0)
),
UserPostStats as (
    select
        p.OwnerUserId,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsPosted,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersPosted,
        sum(coalesce(p.Score,0)) as TotalScore,
        avg(coalesce(length(p.Body) - length(replace(p.Body, ' ', '')) + 1, 0)) filter (where p.PostTypeId = 1) as AvgWordsInQuestion,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
PostWithAnswerAndVotes as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerUserId,
        a.CreationDate as AnswerDate,
        v.VoteTypeId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Votes v on a.Id = v.PostId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, a.Id, a.OwnerUserId, a.CreationDate, v.VoteTypeId
),
UserRankAnswers as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.CreationDate,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate) ranking
    from Posts p
    where p.PostTypeId = 2
),
ClosedQuestionRanks as (
    select
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    left join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where ph.PostHistoryTypeId = 10
)
select distinct
    u.Id as User_Id,
    u.DisplayName,
    u.Reputation,
    s.TotalPosts,
    s.QuestionsPosted,
    s.AnswersPosted,
    s.TotalScore,
    coalesce(rbc.BadgeCount,0) as NonTagBadges,
    cs.CloseReason,
    pq.Title as LatestClosedQuestionTitle,
    pq.CreationDate as LatestClosedQuestionDate,
    coalesce(upa.ranking,0) as UserAnswerRank,
    stg.TopTags
from Users u
    left join UserPostStats s on u.Id = s.OwnerUserId
    left join (
        select UserId, sum(BadgeCount) as BadgeCount
        from RecursiveBadgeCte
        group by UserId
    ) rbc on u.Id = rbc.UserId
    left join (
        select cq.PostId, cq.CreationDate, cq.Title, cris.CloseReason
        from Posts cq
        inner join (
            select PostId, max(CreationDate) as MaxDate from PostHistory where PostHistoryTypeId = 10 group by PostId
        ) phm on cq.Id = phm.PostId
        inner join PostHistory crisch on phm.PostId = crisch.PostId and phm.MaxDate = crisch.CreationDate and crisch.PostHistoryTypeId = 10
        left join CloseReasonTypes cris on cris.Id::text = crisch.Comment
    ) pq on u.Id = pq.OwnerUserId
    left join ClosedQuestionRanks cs on pq.Id = cs.PostId and cs.rn = 1
    left join UserRankAnswers upa on u.Id = upa.OwnerUserId
    left join (
        select
            owp.OwnerUserId,
            string_agg(distinct t.TagName, ', ' order by sum(owp.Count) desc) as TopTags
        from Posts pq
        join lateral (
            select unnest(string_to_array(substring(pq.Tags from 2 for length(pq.Tags) - 2), '><')) as TagName
        ) tags on true
        join Tags t on tags.TagName = t.TagName
        join (select OwnerUserId, Count(*) from Posts group by OwnerUserId) owp on owp.OwnerUserId = pq.OwnerUserId
        group by owp.OwnerUserId
    ) stg on u.Id = stg.OwnerUserId
where u.Reputation > 1000
and (pq.CreationDate is null or pq.CreationDate > '2020-01-01')
order by s.TotalScore desc nulls last, s.TotalPosts desc nulls last
limit 100;