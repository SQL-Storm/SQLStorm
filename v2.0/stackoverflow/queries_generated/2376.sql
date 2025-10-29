-- {"query": "2376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1224} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreation,
        p.Score,
        p.ViewCount,
        p.Tags,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryCreationDate,
        ph.Text as HistoryText,
        row_number() over(partition by u.Id order by p.CreationDate desc) as UserPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id and b.Date <= current_timestamp
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
    where u.Reputation > 500 and (p.PostTypeId = 1 or p.PostTypeId is null)
),
UserTagCounts as (
    select
      r.UserId,
      unnest(string_to_array(coalesce(r.Tags,''),'><')) as Tag
    from RecursiveUserActivity r
    where r.Tags is not null
),
TopUserTags as (
    select
      UserId, 
      Tag,
      count(*) as TagCount,
      rank() over(partition by UserId order by count(*) desc) as Rank
    from UserTagCounts
    group by UserId, Tag
    having count(*) > 1
),
UserTopTagSummary as (
    select
      u.UserId,
      string_agg(distinct t.Tag || '(' || t.TagCount || ')', ', ' order by t.TagCount desc) as TopTagsSummary
    from TopUserTags t
    join Users u on u.Id = t.UserId
    where t.Rank <= 3
    group by u.Id
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) filter(where p.Score > 0) as PositiveAnswers,
        count(*) as TotalAnswers,
        avg(p.Score) as AvgAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2
    group by p.ParentId
),
LatestComments as (
    select
        c.PostId,
        c.UserId,
        c.CreationDate,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRank,
        coalesce(c.Text, '[no comment text]') as CommentText
    from Comments c
),
FilteredLatestComments as (
    select 
      PostId,
      UserId,
      CreationDate,
      CommentText
    from LatestComments
    where CommentRank = 1
),
DuplicateQuestions as (
  select 
    pl.PostId as DuplicatePostId,
    pl.RelatedPostId as OriginalPostId,
    p1.Title as DuplicateTitle,
    p2.Title as OriginalTitle,
    u.DisplayName as DuplicateOwner,
    ph.Comment as CloseReason,
    row_number() over(partition by pl.PostId order by pl.CreationDate desc) as DupRank
  from PostLinks pl
  join Posts p1 on p1.Id = pl.PostId
  join Posts p2 on p2.Id = pl.RelatedPostId
  left join Users u on u.Id = p1.OwnerUserId
  left join PostHistory ph on ph.PostId = p1.Id and ph.PostHistoryTypeId = 10
  where pl.LinkTypeId = 3 and p1.PostTypeId = 1 and p2.PostTypeId = 1
),
FinalDuplicateQuestions as (
  select * from DuplicateQuestions where DupRank = 1
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        row_number() over(order by u.Reputation desc) as RepRank,
        ntile(4) over(order by u.Reputation desc) as RepQuartile
    from Users u
    where u.DisplayName is not null
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.RepQuartile,
    coalesce(s.TopTagsSummary, 'None') as TopTags,
    coalesce(a.PositiveAnswers,0) as PositiveAnswers,
    coalesce(a.TotalAnswers,0) as TotalAnswers,
    round(coalesce(a.AvgAnswerScore, 0), 2) as AvgAnswerScore,
    coalesce(a.UpVotes,0) as UpVotes,
    coalesce(a.DownVotes,0) as DownVotes,
    fmc.CreationDate as LatestCommentDate,
    fmc.CommentText as LatestComment,
    dq.DuplicatePostId,
    dq.OriginalPostId,
    dq.DuplicateTitle,
    dq.OriginalTitle,
    dq.CloseReason
from UserReputationWindow u
left join AnswerStats a on a.QuestionId in (
    select Id from Posts where OwnerUserId = u.Id and PostTypeId = 1
)
left join UserTopTagSummary s on s.UserId = u.Id
left join FilteredLatestComments fmc on fmc.UserId = u.Id
left join FinalDuplicateQuestions dq on dq.DuplicatePostId in (
    select Id from Posts where OwnerUserId = u.Id and PostTypeId = 1
)
where u.Reputation > 1000
order by u.Reputation desc, a.PositiveAnswers desc
limit 100;