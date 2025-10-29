-- {"query": "2995.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1437} 
with recursive TagHierarchy(tag_id, parent_tag_id, depth) as (
    select t.Id, null::int, 0
    from Tags t
    where t.IsRequired = 1
  union all
    select t.Id, th.tag_id, th.depth + 1
    from Tags t
    join TagHierarchy th on t.WikiPostId = th.tag_id
    where t.IsRequired = 0
),
RecentActiveUsers as (
  select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
         count(distinct p.Id) as QuestionCount,
         count(distinct a.Id) as AnswerCount,
         coalesce(sum(vt_up.VoteCount),0) as UpVotesReceived,
         coalesce(sum(vt_down.VoteCount),0) as DownVotesReceived,
         row_number() over (order by u.Reputation desc, u.CreationDate asc) as rn
  from Users u
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 -- questions
  left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2 -- answers
  left join (
      select PostId, count(*) as VoteCount
      from Votes
      where VoteTypeId = 2 -- UpMod
      group by PostId
  ) vt_up on vt_up.PostId in (
      select Id from Posts where OwnerUserId = u.Id
  )
  left join (
      select PostId, count(*) as VoteCount
      from Votes
      where VoteTypeId = 3 -- DownMod
      group by PostId
  ) vt_down on vt_down.PostId in (
      select Id from Posts where OwnerUserId = u.Id
  )
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionDuplicateLinks as (
  select pl.PostId question_id, pl.RelatedPostId duplicate_of_question_id, count(*) over (partition by pl.PostId) as DuplicateCount
  from PostLinks pl
  join Posts p on p.Id = pl.PostId and p.PostTypeId = 1 -- questions only
  where pl.LinkTypeId = 3 -- Duplicate
),
TopBadges as (
  select b.UserId, b.Name as BadgeName, b.Class, count(*) over (partition by b.UserId) as TotalBadges,
  row_number() over (partition by b.UserId order by b.Class asc, b.Date desc) as rn
  from Badges b
),
UserTopBadges as (
  select UserId, BadgeName, Class
  from TopBadges
  where rn <= 3
),
UserQuestionStats as (
  select p.OwnerUserId as UserId,
         count(*) filter (where p.Score > 10) as HighlyRatedQuestions,
         count(*) filter (where p.ViewCount > 1000) as PopularQuestions,
         sum(coalesce(p.Score, 0)) as TotalQuestionScore,
         max(p.CreationDate) as LastQuestionDate
  from Posts p
  where p.PostTypeId = 1
  group by p.OwnerUserId
),
CommentsWithNonNullText as (
  select c.Id, c.PostId, c.UserId, c.CreationDate,
         length(c.Text) as TextLength,
         case when position('<code>' in c.Text) > 0 then 1 else 0 end as HasCodeSnippet
  from Comments c
  where c.Text is not null
),
UserCommentActivity as (
  select c.UserId,
         count(*) as CommentCount,
         sum(TextLength) as TotalCommentLength,
         sum(HasCodeSnippet) as CommentsWithCodeSnippet
  from CommentsWithNonNullText c
  group by c.UserId
)
select u.Id as UserId,
       u.DisplayName,
       u.Reputation,
       u.CreationDate,
       ru.QuestionCount,
       ru.AnswerCount,
       ru.UpVotesReceived,
       ru.DownVotesReceived,
       coalesce(uqs.HighlyRatedQuestions,0) as HighlyRatedQuestions,
       coalesce(uqs.PopularQuestions,0) as PopularQuestions,
       coalesce(uqs.TotalQuestionScore,0) as TotalQuestionScore,
       coalesce(uca.CommentCount,0) as CommentCount,
       coalesce(uca.TotalCommentLength,0) as TotalCommentLength,
       coalesce(uca.CommentsWithCodeSnippet,0) as CommentsWithCodeSnippet,
       string_agg(distinct utb.BadgeName || '(' || case utb.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ' order by utb.Class) as TopBadges,
       coalesce(dd.DuplicateCount,0) as DuplicatesOnUserQuestions,
       lag(ru.UpVotesReceived) over (order by u.Reputation desc) as PrevUserUpVotes,
       lead(ru.UpVotesReceived) over (order by u.Reputation desc) as NextUserUpVotes,
       case
          when u.Location is null or u.Location = '' then 'Unknown'
          else upper(substr(u.Location,1,1)) || lower(substr(u.Location,2))
       end as NormalizedLocation,
       greatest(
           extract(epoch from (current_timestamp - ru.CreationDate)) / 86400, -- days since first post
           0
       ) as DaysSinceUserFirstPost,
       case
          when u.EmailHash is not null then md5(u.EmailHash || coalesce(u.DisplayName,''))
          else null
       end as HashedUserIdentity,
       coalesce(th.depth, -1) as UserPreferredTagDepth
from Users u
left join RecentActiveUsers ru on ru.Id = u.Id
left join UserQuestionStats uqs on uqs.UserId = u.Id
left join UserCommentActivity uca on uca.UserId = u.Id
left join UserTopBadges utb on utb.UserId = u.Id
left join (
  select OwnerUserId, sum(DuplicateCount) as DuplicateCount
  from QuestionDuplicateLinks qdl
  group by OwnerUserId
) dd on dd.OwnerUserId = u.Id
left join LATERAL (
  select th.depth
  from Tags t
  join TagHierarchy th on th.tag_id = t.Id
  where t.Id in (
      select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))
      from Posts p
      where p.OwnerUserId = u.Id and p.PostTypeId = 1 limit 1
  )
  order by th.depth limit 1
) th on true
where u.Reputation > 1000
order by u.Reputation desc
limit 50;