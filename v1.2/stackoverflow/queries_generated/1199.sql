-- {"query": "1199.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2141} 
with RecursivePostLinks as (
  select pl.PostId, pl.RelatedPostId, pl.LinkTypeId, 1 as depth
  from PostLinks pl
  where pl.LinkTypeId = 1 -- linked
  union all
  select rpl.PostId, pl.RelatedPostId, pl.LinkTypeId, rpl.depth + 1
  from PostLinks pl
  join RecursivePostLinks rpl on pl.PostId = rpl.RelatedPostId
  where pl.LinkTypeId = 1 and rpl.depth < 3
),
UserBadgeSummary as (
  select
    b.UserId,
    count(*) as TotalBadges,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    bool_or(b.TagBased = 1) as HasTagBasedBadges
  from Badges b
  group by b.UserId
),
PostScoreStats as (
  select
    p.OwnerUserId,
    p.Id as PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as ScoreRank,
    rank() over (partition by p.OwnerUserId order by p.CreationDate) as ChronoRank
  from Posts p
  where p.OwnerUserId is not null
),
TopUserPosts as (
  select ps.*
  from PostScoreStats ps
  where ps.ScoreRank <= 5
),
QuestionAnswerRatios as (
  select
    u.Id as UserId,
    coalesce(questions.QuestionCount,0) as QuestionCount,
    coalesce(answers.AnswerCount,0) as AnswerCount,
    case when coalesce(answers.AnswerCount,0) + coalesce(questions.QuestionCount,0) = 0 then null
         else round(1.0 * coalesce(answers.AnswerCount,0) / nullif(coalesce(questions.QuestionCount,0), 0), 2)
    end as AnswerQuestionRatio
  from Users u
  left join (
    select OwnerUserId, count(*) as QuestionCount
    from Posts
    where PostTypeId = 1
      and OwnerUserId is not null
    group by OwnerUserId
  ) questions on questions.OwnerUserId = u.Id
  left join (
    select OwnerUserId, count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
      and OwnerUserId is not null
    group by OwnerUserId
  ) answers on answers.OwnerUserId = u.Id
  where u.Reputation > 1000
),
UserActivityWindow as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    count(p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
    count(p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
    count(c.Id) as TotalComments,
    max(p.CreationDate) as LastPostDate,
    avg(p.Score) filter (where p.Score is not null) as AvgPostScore,
    avg(vs.UpVotes) as AvgUpVotes,
    avg(vs.DownVotes) as AvgDownVotes,
    sum(case when p.ClosedDate is not null then 1 else 0 end) as ClosedPostsCount
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join (
    select 
      p.OwnerUserId,
      sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
      sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.OwnerUserId is not null
    group by p.OwnerUserId
  ) vs on vs.OwnerUserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostsWithCommentsAndVotes as (
  select
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    count(distinct c.Id) as CommentCount,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostScoreRank,
    coalesce(t.Name, 'No Link') as TopLinkTypeName
  from Posts p
  left join Comments c on c.PostId = p.Id
  left join Votes v on v.PostId = p.Id
  left join PostLinks pl on pl.PostId = p.Id
  left join LinkTypes t on t.Id = pl.LinkTypeId
  group by p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, t.Name
),
HighScoringQuestionsWithAcceptedAnns as (
  select
    q.Id as QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    ans.Id as AcceptedAnswerId,
    ans.Score as AcceptedAnswerScore,
    ans.OwnerUserId as AnswererUserId,
    coalesce(u.DisplayName, 'Anonymous') as AnswererDisplayName,
    qs.TagCount,
    qs.Tags,
    case when q.ClosedDate is null then 'Open' else 'Closed' end as Status
  from Posts q
  left join Posts ans on ans.Id = q.AcceptedAnswerId
  left join Users u on ans.OwnerUserId = u.Id
  cross join lateral (
    select array_length(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><'),1) as TagCount,
           q.Tags
  ) qs
  where q.PostTypeId = 1
    and q.Score > 100
),
PostsWithCloseInfo as (
  select
    p.Id,
    p.Title,
    p.CreationDate,
    p.ClosedDate,
    coalesce(cr.Name, 'Not Closed') as CloseReasonName,
    ph.Comment as CloseReasonCode,
    ph.CreationDate as CloseVoteDate,
    ph.UserId as CloseVoterUserId
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes cr on cr.Id::int = ph.Comment::int
),
UserVsAvgScores as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(p.Id) as NumPosts,
    avg(p.Score) as AvgPostScore,
    avg(coalesce(p.ViewCount,0)) as AvgViewCount,
    max(p.Score) as MaxScore,
    percentile_cont(0.5) within group (order by p.Score) as MedianScore,
    ws.TotalBadges,
    ws.GoldBadges,
    ws.SilverBadges,
    ws.BronzeBadges,
    ws.HasTagBasedBadges,
    qars.AnswerQuestionRatio
  from Users u
  left join Posts p on p.OwnerUserId = u.Id and p.Score is not null
  left join UserBadgeSummary ws on ws.UserId = u.Id
  left join QuestionAnswerRatios qars on qars.UserId = u.Id
  group by u.Id, u.DisplayName, ws.TotalBadges, ws.GoldBadges, ws.SilverBadges, ws.BronzeBadges, ws.HasTagBasedBadges, qars.AnswerQuestionRatio
  having count(p.Id) > 10
)
select
  uvs.UserId,
  uvs.DisplayName,
  uvs.NumPosts,
  uvs.AvgPostScore,
  uvs.MedianScore,
  uvs.MaxScore,
  uvs.AvgViewCount,
  coalesce(ua.TotalQuestions, 0) as TotalQuestions,
  coalesce(ua.TotalAnswers, 0) as TotalAnswers,
  uvs.TotalBadges,
  uvs.GoldBadges,
  uvs.SilverBadges,
  uvs.BronzeBadges,
  uvs.HasTagBasedBadges,
  uvs.AnswerQuestionRatio,
  coalesce(pwc.ClosedPostsCount, 0) as ClosedPostsCount,
  case 
    when uvs.AnswerQuestionRatio is null then 'No activity on Q&A'
    when uvs.AnswerQuestionRatio > 2 then 'Mostly answering'
    when uvs.AnswerQuestionRatio between 0.5 and 2 then 'Balanced Q&A'
    else 'Mostly questioning'
  end as UserType,
  (select count(*) from Posts p where p.OwnerUserId = uvs.UserId and p.PostTypeId = 1 and p.Score > (select avg(Score) from Posts where PostTypeId=1)) as AboveAverageQuestions,
  (select count(*) from Posts p where p.OwnerUserId = uvs.UserId and p.PostTypeId = 2 and p.Score > (select avg(Score) from Posts where PostTypeId=2)) as AboveAverageAnswers
from UserVsAvgScores uvs
left join UserActivityWindow ua on ua.UserId = uvs.UserId
left join UserActivityWindow pwc on pwc.UserId = uvs.UserId
order by uvs.GoldBadges desc, uvs.AvgPostScore desc, uvs.NumPosts desc
limit 100;