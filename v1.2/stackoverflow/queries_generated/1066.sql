-- {"query": "1066.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1158} 
with RecursiveUserBadges as (
    select u.Id as UserId,
           u.DisplayName,
           b.Name as BadgeName,
           b.Class as BadgeClass,
           row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
      from Users u
      left join Badges b on u.Id = b.UserId
), RecursiveHighScorePosts as (
    select p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.CreationDate, 1 as Depth
      from Posts p
     where p.Score > 100
    union all
    select p2.Id, p2.OwnerUserId, p2.PostTypeId, p2.Score, p2.CreationDate, rh.Depth + 1
      from Posts p2
      join RecursiveHighScorePosts rh on p2.ParentId = rh.Id
     where p2.Score > 50 and rh.Depth < 3
), RankedAnswers as (
    select p.Id, p.ParentId,
           row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank,
           count(*) over (partition by p.ParentId) as AnswersCount
      from Posts p
     where p.PostTypeId = 2
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
      from PostLinks pl
      join LinkTypes lt on pl.LinkTypeId = lt.Id
     where lt.Name = 'Duplicate'
), UserActivity as (
    select u.Id, u.DisplayName,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
           coalesce(sum(v.VoteTypeCount),0) as VotesCast,
           coalesce(sum(cmt.CommentCount),0) as CommentsMade
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
      left join (
        select v.UserId, count(*) as VoteTypeCount
          from Votes v
      group by v.UserId
      ) v on v.UserId = u.Id
      left join (
        select c.UserId, count(*) as CommentCount
          from Comments c
      group by c.UserId
      ) cmt on cmt.UserId = u.Id
  group by u.Id, u.DisplayName
), PostActivityWindows as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.Score,
           p.CreationDate, p.ViewCount,
           rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
           dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RecencyRank,
           sum(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 5 preceding and current row) as RollingScore5Posts
      from Posts p
     where p.Score is not null
)
select ua.DisplayName,
       ua.QuestionsPosted,
       ua.AnswersPosted,
       ua.VotesCast,
       ua.CommentsMade,
       rb.BadgeName,
       rb.BadgeClass,
       rhp.Id as HighScorePostId,
       rhp.Score as HighScore,
       rap.AnswerRank,
       rap.AnswersCount,
       dl.RelatedPostId as DuplicateOf,
       dl.LinkTypeName,
       pa.ScoreRank,
       pa.RecencyRank,
       pa.RollingScore5Posts,
       coalesce(nullif(p.Tags, ''), '<no tags>') as Tags,
       case 
         when ua.QuestionsPosted > 10 and ua.AnswersPosted > 5 then 'Active Contributor'
         when ua.QuestionsPosted > 0 and ua.AnswersPosted = 0 then 'Question Asker'
         when ua.AnswersPosted > 0 and ua.QuestionsPosted = 0 then 'Answerer'
         else 'Other'
       end as ContributorType,
       coalesce(trim(split_part(p.Title, ' ', 1)), '[No Title]') as FirstWordInTitle,
       (select count(1)
          from Comments c2
         where c2.PostId = p.Id
           and (c2.Text ~* '(error|fail|bug)')
           and c2.Score > 0) as HelpfulErrorCommentsCount
  from UserActivity ua
  left join RecursiveUserBadges rb on rb.UserId = ua.Id and rb.BadgeRank = 1
  left join RecursiveHighScorePosts rhp on rhp.OwnerUserId = ua.Id
  left join RankedAnswers rap on rap.ParentId = rhp.Id and rap.AnswerRank = 1
  left join Posts p on p.Id = rhp.Id
  left join DuplicateLinks dl on dl.PostId = rhp.Id
  left join PostActivityWindows pa on pa.Id = rhp.Id
 where ua.VotesCast > 0
   and (rb.BadgeClass is null or rb.BadgeClass <= 2)
union
select '[Summary]' as DisplayName,
       sum(QuestionsPosted),
       sum(AnswersPosted),
       sum(VotesCast),
       sum(CommentsMade),
       null,
       null,
       null,
       null,
       null,
       null,
       null,
       null,
       null,
       null,
       null,
       null
  from UserActivity;