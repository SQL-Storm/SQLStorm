-- {"query": "1190.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1282} 
with RecursiveTagPairs as (
    select 
        p.Id as QuestionId,
        p.Title,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPairCounts as (
    select
        t1.Tag as Tag1,
        t2.Tag as Tag2,
        count(distinct t1.QuestionId) as CoOccurCount
    from RecursiveTagPairs t1
    join RecursiveTagPairs t2 
      on t1.QuestionId = t2.QuestionId and t1.Tag < t2.Tag
    group by t1.Tag, t2.Tag
),
TopTagPairs as (
    select Tag1, Tag2, CoOccurCount,
        row_number() over (order by CoOccurCount desc) as rn
    from TagPairCounts
    where CoOccurCount > 5
),
UserAnswerStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(a.Id) filter (where a.Score >= 10) as HighScoreAnswers,
        count(a.Id) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        bool_or(a.Score is null) as HasNullScores
    from Users u
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id, u.DisplayName
),
BadgeRanks as (
    select
        b.UserId,
        b.Name,
        b.Class,
        dense_rank() over (partition by b.Class order by count(*) desc) as RankWithinClass
    from Badges b
    group by b.UserId, b.Name, b.Class
),
UserBadgesSummary as (
    select
        UserId,
        count(*) as BadgeCount,
        max(Class) as HighestBadgeClass,
        max(case when TagBased = 1 then 1 else 0 end) as HasTagBasedBadges
    from Badges
    group by UserId
),
RecentActiveQuestions as (
  select 
    p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate, p.AcceptedAnswerId,
    (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
    p.OwnerUserId,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate > current_date - interval '90 days'
),
QuestionsWithAnswers as (
  select 
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.Score as QuestionScore,
    q.ViewCount,
    q.CreationDate as QuestionCreationDate,
    a.Id as AnswerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate,
    u.DisplayName as AnswerOwnerName,
    coalesce(
      (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2), 0
    ) as AnswerUpVotes,
    coalesce(
      (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3), 0
    ) as AnswerDownVotes
  from RecentActiveQuestions q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Users u on u.Id = a.OwnerUserId
  where q.rn <= 5
),
RankedUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        count(distinct b.Id) as BadgesCount,
        row_number() over (order by count(distinct p.Id) desc, count(distinct c.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
LastEditByOwnerOrNot as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.LastEditorUserId,
        case 
          when p.LastEditorUserId is null then 'No Editor' 
          when p.OwnerUserId = p.LastEditorUserId then 'Owner'
          else 'Other'
        end as LastEditRelation
    from Posts p
    where p.PostTypeId = 1
)
select 
    u.DisplayName as User,
    u.Reputation,
    uas.TotalAnswers,
    uas.HighScoreAnswers,
    ubs.BadgeCount,
    ubs.HasTagBasedBadges,
    q.QuestionId,
    q.Title as RecentQuestion,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerId,
    q.AnswerScore,
    q.AnswerUpVotes,
    q.AnswerDownVotes,
    ttp.Tag1,
    ttp.Tag2,
    ttp.CoOccurCount,
    l.LastEditRelation,
    ras.ActivityRank
from UserAnswerStats uas
join Users u on u.Id = uas.UserId
left join UserBadgesSummary ubs on ubs.UserId = u.Id
left join QuestionsWithAnswers q on q.OwnerUserId = u.Id
left join TopTagPairs ttp on ttp.rn = 1
left join LastEditByOwnerOrNot l on l.OwnerUserId = u.Id
left join RankedUserActivity ras on ras.UserId = u.Id
where uas.TotalAnswers > 5
  and (ubs.BadgeCount is null or ubs.BadgeCount > 2)
order by uas.HighScoreAnswers desc, q.AnswerUpVotes desc
limit 100;