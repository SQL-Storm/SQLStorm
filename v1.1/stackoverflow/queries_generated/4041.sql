-- {"query": "4041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1103} 
with RecursiveUserBadges as (
    select u.Id as UserId,
           u.DisplayName,
           b.Name as BadgeName,
           b.Class,
           row_number() over (partition by u.Id order by b.Date desc, b.Name) as rn
      from Users u
      left join Badges b on b.UserId = u.Id and b.Class in (1,2,3)
     where u.Reputation > 1000
), LatestPosts as (
    select p.Id,
           p.OwnerUserId,
           p.PostTypeId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.Tags,
           p.Title,
           p.AcceptedAnswerId,
           string_agg(distinct lt.Name, ',') filter (where lt.Name is not null) as LinkTypesNames
      from Posts p
      left join PostLinks pl on pl.PostId = p.Id
      left join LinkTypes lt on lt.Id = pl.LinkTypeId
     group by p.Id
), AnswerStats as (
    select p.ParentId as QuestionId,
           count(*) as TotalAnswers,
           avg(p.Score) as AvgAnswerScore,
           max(p.Score) as MaxAnswerScore,
           sum(case when p.Score < 0 then 1 else 0 end) as NegativeAnswers,
           sum(case when p.OwnerUserId is null then 1 else 0 end) as AnonymousAnswerCount
      from Posts p
     where p.PostTypeId = 2
     group by p.ParentId
), Closures as (
    select ph.PostId,
           count(*) as CloseCount,
           bool_or(ph.PostHistoryTypeId = 10) as IsClosed,
           max((select Name from CloseReasonTypes crt where crt.Id = cast(ph.Comment as int))) as CloseReason
      from PostHistory ph
     where ph.PostHistoryTypeId in (10,11)
     group by ph.PostId
), UserActivity as (
    select u.Id as UserId,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
           count(distinct c.Id) as CommentsMade,
           max(p.CreationDate) as LastPostDate,
           max(c.CreationDate) as LastCommentDate
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
      left join Comments c on c.UserId = u.Id
     group by u.Id
), RankedQuestions as (
    select p.Id,
           p.OwnerUserId,
           p.Score,
           p.ViewCount,
           p.Tags,
           row_number() over (
             partition by p.OwnerUserId 
             order by p.ViewCount desc nulls last, p.Score desc nulls last, p.CreationDate desc
           ) as Rnk
      from Posts p
     where p.PostTypeId = 1 and p.ViewCount is not null
)
select u.Id as UserId,
       u.DisplayName,
       u.Reputation,
       ua.QuestionsPosted,
       ua.AnswersPosted,
       ua.CommentsMade,
       ua.LastPostDate,
       ua.LastCommentDate,
       array_agg(distinct rqb.Tags) filter (where rqb.Rnk <= 3) as Top3Tags,
       rb.BadgeName as MostRecentBadge,
       rb.Class as BadgeClass,
       lp.Id as RecentHighViewPostId,
       lp.Title as RecentHighViewPostTitle,
       lp.ViewCount as RecentHighViewPostViews,
       asn.TotalAnswers,
       asn.AvgAnswerScore,
       asn.NegativeAnswers,
       c.IsClosed,
       c.CloseCount,
       c.CloseReason,
       case 
         when strpos(lp.Tags, '<sql>') > 0 then 'Contains <sql> tag'
         when strpos(lp.Tags, '<performance>') > 0 then 'Contains <performance> tag'
         else 'Other Tags'
       end as TagCategory,
       (select count(*) 
          from Votes v 
         where v.PostId = lp.Id and v.VoteTypeId = 2) as UpVotesOnPost,
       (select count(*) 
          from Votes v 
         where v.PostId = lp.Id and v.VoteTypeId = 3) as DownVotesOnPost
  from Users u
  left join UserActivity ua on ua.UserId = u.Id
  left join RecursiveUserBadges rb on rb.UserId = u.Id and rb.rn = 1
  left join RankedQuestions rqb on rqb.OwnerUserId = u.Id and rqb.Rnk = 1
  left join LatestPosts lp on lp.Id = rqb.Id
  left join AnswerStats asn on asn.QuestionId = rqb.Id
  left join Closures c on c.PostId = rqb.Id
 where u.Reputation > 1000
   and ua.QuestionsPosted > 0
   and (c.IsClosed is null or c.IsClosed = false) 
   and (lp.ViewCount > 1000 or lp.ViewCount is null)
 order by ua.QuestionsPosted desc nulls last, u.Reputation desc nulls last
 limit 50;