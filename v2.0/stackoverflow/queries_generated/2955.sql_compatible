with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class, b.Date,
           row_number() over (partition by u.Id order by b.Date desc) as rn
      from Users u
      left join Badges b
        on u.Id = b.UserId
     where b.Class is not null
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
      from RecursiveUserBadges
     where rn <= 3
),
PostCommentCounts as (
    select p.Id as PostId, count(c.Id) as CommentCount
      from Posts p
      left join Comments c on p.Id = c.PostId
     group by p.Id
),
PostScoreRanks as (
    select p.Id, p.PostTypeId, p.Title, p.Score,
           rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
      from Posts p
),
ClosedQuestionsCTE as (
    select ph.PostId, ph.CreationDate, crt.Name as CloseReason
      from PostHistory ph
      join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
      left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
),
UserActivityWindow as (
    select u.Id, u.DisplayName,
           -- rewrite distinct counts per user using subqueries aggregated, then join is simpler.
           (select count(distinct p1.Id) from Posts p1 where p1.OwnerUserId = u.Id and p1.PostTypeId = 1) as QuestionCount,
           (select count(distinct p2.Id) from Posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 2) as AnswerCount,
           (select count(distinct c1.Id) from Comments c1 where c1.UserId = u.Id) as CommentCount,
           row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn
      from Users u
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(u.Views,0) as Views,
    coalesce(u.UpVotes,0) as UpVotes,
    coalesce(u.DownVotes,0) as DownVotes,
    coalesce(tq.QuestionCount,0) as TotalQuestions,
    coalesce(tq.AnswerCount,0) as TotalAnswers,
    coalesce(tq.CommentCount,0) as TotalComments,
    tb.BadgeName,
    case when tb.Class = 1 then 'Gold'
         when tb.Class = 2 then 'Silver'
         when tb.Class = 3 then 'Bronze'
         else 'Unknown' end as BadgeClass,
    pc.CommentCount as PostCommentCount,
    ps.ScoreRank as PostScoreRank,
    cq.CloseReason,
    substr(regexp_replace(trim(coalesce(p.Tags,'')), '^<|>$', '', 'g'), 1, 100) as TagsPreview,
    case when u.WebsiteUrl is null or trim(u.WebsiteUrl) = '' then 'No Website'
         else concat('Website: ', left(u.WebsiteUrl, 50), case when length(u.WebsiteUrl) > 50 then '...' else '' end) end as WebsiteSummary,
    (
        select p2.Title
          from Posts p2
         where p2.LastEditorUserId = u.Id
         order by p2.LastEditDate desc
         limit 1
    ) as LastEditedPostTitle,
    case when u.AboutMe is null then 'No About Me info'
         when length(u.AboutMe) > 60 then substr(u.AboutMe,1,57) || '...'
         else u.AboutMe
    end as AboutMeSnippet
from Users u
left join UserActivityWindow tq on u.Id = tq.Id and tq.rn = 1
left join TopBadges tb on tb.UserId = u.Id
left join Posts p on u.Id = p.OwnerUserId and p.PostTypeId = 1
left join PostCommentCounts pc on p.Id = pc.PostId
left join PostScoreRanks ps on p.Id = ps.Id
left join ClosedQuestionsCTE cq on p.Id = cq.PostId
where u.Reputation > 1000
  and (coalesce(tq.QuestionCount,0) > 5 or coalesce(tq.AnswerCount,0) > 10)
  and (
      tb.Class = 1 or tb.Class = 2 or tb.Class is null
  )
union
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    0 as Views,
    0 as UpVotes,
    0 as DownVotes,
    0 as TotalQuestions,
    0 as TotalAnswers,
    0 as TotalComments,
    null as BadgeName,
    null as BadgeClass,
    0 as PostCommentCount,
    null as PostScoreRank,
    null as CloseReason,
    null as TagsPreview,
    'No Website' as WebsiteSummary,
    null as LastEditedPostTitle,
    'No About Me info' as AboutMeSnippet
  from Users u
 where not exists (select 1 from Posts p where p.OwnerUserId = u.Id)
order by Reputation desc, DisplayName
limit 100;