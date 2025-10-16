-- {"query": "4051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1031} 
with RecursiveBadges as (
    select b.Id, b.UserId, b.Name, b.Date, b.Class, b.TagBased,
           row_number() over (partition by b.UserId order by b.Date) as rn
    from Badges b
    where b.Date > '2020-01-01'
), LatestBadges as (
    select rb.UserId, string_agg(rb.Name || ' (' || case rb.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ' order by rb.rn) as BadgeSummary
    from RecursiveBadges rb
    where rb.rn <= 5
    group by rb.UserId
), QuestionAnswers as (
    select q.Id as QuestionId, q.Title, q.CreationDate as QuestionDate, q.Score as QuestionScore, q.Tags,
           a.Id as AnswerId, a.OwnerUserId as AnswerUserId, a.Score as AnswerScore, a.CreationDate as AnswerDate,
           u.DisplayName as AnswerUserName,
           row_number() over (partition by q.Id order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
), CloseReasonsCount as (
    select p.Id as PostId,
           count(distinct case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseVotesCount,
           max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) end) as LatestCloseReasonId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id
), UserReputationRanks as (
    select u.Id as UserId, u.DisplayName, u.Reputation,
           rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    where u.Reputation is not null
), TagUsage as (
    select unnest(string_to_array(trim(both '<>' from Tags), '><')) as Tag,
           count(*) as PostCount
    from Posts
    where PostTypeId = 1 and Tags is not null
    group by Tag
    having count(*) > 10
), UserTopTags as (
    select u.Id as UserId,
           tu.Tag,
           row_number() over (partition by u.Id order by count(*) desc) as TagRank,
           count(*) as TagCount
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    join lateral unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as tu(Tag)
    where p.PostTypeId = 1 and u.Id is not null
    group by u.Id, tu.Tag
    having count(*) > 2
)
select q.QuestionId,
       q.Title,
       q.QuestionDate,
       q.QuestionScore,
       coalesce(crc.CloseVotesCount, 0) as CloseVotesCount,
       crt.Name as LatestCloseReason,
       q.AnswerId,
       q.AnswerUserId,
       coalesce(q.AnswerUserName, '[anonymous]') as AnswerUserName,
       q.AnswerScore,
       q.AnswerDate,
       ur.Reputation,
       ur.ReputationRank,
       lt.BadgeSummary,
       string_agg(distinct tu.Tag || ' (' || cast(tu.TagCount as varchar) || ')', ', ') within group (order by tu.TagCount desc) as UserTopTags,
       string_agg(distinct tu2.Tag, ', ') within group (order by tu2.PostCount desc) as PopularTags
from QuestionAnswers q
left join CloseReasons crt on crt.Id = (select max(Comment::int) from PostHistory ph where ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10)
left join CloseReasonsCount crc on crc.PostId = q.QuestionId
left join Users u on u.Id = q.AnswerUserId
left join UserReputationRanks ur on ur.UserId = q.AnswerUserId
left join LatestBadges lt on lt.UserId = q.AnswerUserId
left join UserTopTags tu on tu.UserId = q.AnswerUserId and tu.TagRank <= 3
left join TagUsage tu2 on true
where q.AnswerRank <= 3
group by q.QuestionId, q.Title, q.QuestionDate, q.QuestionScore, crc.CloseVotesCount, crt.Name, q.AnswerId, q.AnswerUserId, q.AnswerUserName, q.AnswerScore, q.AnswerDate, ur.Reputation, ur.ReputationRank, lt.BadgeSummary
order by q.QuestionScore desc nulls last, q.QuestionDate desc
limit 50;