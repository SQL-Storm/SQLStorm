-- {"query": "708.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1215} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class, b.Date,
           row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
), UserTopBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where BadgeRank <= 3
), PostVotesSummary as (
    select p.Id as PostId,
           count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
           count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
           count(distinct v.UserId) as UniqueVoters
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
), QuestionAnswerStats as (
    select q.Id as QuestionId, q.Title, q.CreationDate as QuestionDate, q.Score as QuestionScore,
           a.Id as AnswerId, a.Score as AnswerScore, a.CreationDate as AnswerDate,
           pvs.UpVotes as AnswerUpVotes, pvs.DownVotes as AnswerDownVotes, pvs.UniqueVoters as AnswerVoters,
           row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostVotesSummary pvs on a.Id = pvs.PostId
    where q.PostTypeId = 1
), TopAnswers as (
    select QuestionId, Title, QuestionDate, QuestionScore,
           AnswerId, AnswerScore, AnswerDate, AnswerUpVotes, AnswerDownVotes, AnswerVoters
    from QuestionAnswerStats
    where AnswerRank = 1
), CloseReasonCounts as (
    select p.Id as PostId, crt.Name as CloseReason, count(ph.Id) as CloseCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    group by p.Id, crt.Name
), TagsExtracted as (
    select p.Id as PostId,
           unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
), TagPopularity as (
    select Tag, count(*) as QuestionCount, avg(Score) as AvgScore
    from TagsExtracted
    group by Tag
    having count(*) > 50
), UserActivityWindow as (
    select u.Id as UserId, u.DisplayName, u.Reputation, u.CreationDate,
           count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
           count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
           sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
           row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as LastPostRank,
           max(p.CreationDate) over (partition by u.Id) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), UserRecentPosts as (
    select distinct UserId, DisplayName, Reputation, CreationDate, QuestionsCount, AnswersCount, TotalPostScore, LastPostDate
    from UserActivityWindow
    where LastPostRank = 1
), CombinedSet as (
    select t.Tag as Entity, 'Tag' as EntityType, QuestionCount as Volume, AvgScore as AvgScore
    from TagPopularity t
    union all
    select u.DisplayName as Entity, 'User' as EntityType, u.AnswersCount + u.QuestionsCount as Volume, coalesce(u.TotalPostScore::float / nullif(u.AnswersCount + u.QuestionsCount,0),0) as AvgScore
    from UserRecentPosts u
    where u.AnswersCount + u.QuestionsCount > 10
)
select cs.EntityType, cs.Entity, cs.Volume, cs.AvgScore,
       crc.CloseReason, crcc.CloseCount,
       tb.BadgeName, tb.Class as BadgeClass,
       concat_ws(' - ', left(p.Title, 50), 'Score:', p.Score::text) as PostSnippet,
       case when p.AcceptedAnswerId is not null then 'Accepted' else 'Not Accepted' end as AcceptanceStatus,
       rank() over (partition by cs.EntityType order by cs.AvgScore desc) as RankByAvgScore
from CombinedSet cs
left join Tags t on t.TagName = cs.Entity and cs.EntityType = 'Tag'
left join Posts p on (p.Id = t.ExcerptPostId or p.Id = t.WikiPostId) and cs.EntityType = 'Tag'
left join CloseReasonCounts crcc on crcc.PostId = p.Id
left join CloseReasonTypes crc on crcc.CloseReason = crc.Name
left join UserTopBadges tb on tb.DisplayName = cs.Entity and cs.EntityType = 'User'
where (crcc.CloseCount is null or crcc.CloseCount < 5)
order by cs.EntityType, RankByAvgScore asc
limit 100;