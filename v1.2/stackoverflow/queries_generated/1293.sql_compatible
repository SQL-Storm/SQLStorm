with RecentHighScoreQuestions as (
    select q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId, u.DisplayName as OwnerName,
           row_number() over (partition by date_trunc('month', q.CreationDate) order by q.Score desc, q.ViewCount desc) as rn
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
      and q.Score > 50
      and q.ViewCount > 1000
), TopAcceptedAnswers as (
    select a.Id, a.ParentId, a.Score, a.OwnerUserId,
           dense_rank() over (order by a.Score desc) as dr
    from Posts a
    inner join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
      and a.Score > 20
), UserBadgeAggregates as (
    select b.UserId,
           count(case when b.Class = 1 then 1 end) as GoldBadges,
           count(case when b.Class = 2 then 1 end) as SilverBadges,
           count(case when b.Class = 3 then 1 end) as BronzeBadges,
           max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), DuplicateQuestions as (
    select q.Id, linked.PostId as DuplicateOfId, lt.Name as LinkTypeName
    from Posts q
    left join PostLinks linked on linked.PostId = q.Id and linked.LinkTypeId = 3
    left join LinkTypes lt on linked.LinkTypeId = lt.Id
    where q.PostTypeId = 1
      and linked.PostId is not null
), CommentsWithUserStatus as (
    select c.Id, c.PostId, c.Score, c.Text, c.CreationDate,
           coalesce(u.DisplayName, c.UserDisplayName) as CommentAuthor,
           case when u.Id is null then 'Anonymous' else 'Registered' end as UserStatus
    from Comments c
    left join Users u on c.UserId = u.Id
), QuestionCloseEvents as (
    select ph.PostId, count(*) as CloseCount,
           array_agg(distinct crt.Name) as CloseReasons
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on 
         -- try to interpret ph.Comment as an integer id; use safe numeric conversion compatible with multiple dialects
         case
           when ph.Comment ~ '^[0-9]+$' then cast(ph.Comment as integer)
           else null
         end = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
)
select rhq.Id as QuestionId,
       rhq.Title,
       rhq.CreationDate as QuestionDate,
       rhq.Score as QuestionScore,
       rhq.ViewCount,
       rhq.OwnerName,
       tpa.Id as TopAnswerId,
       tpa.Score as TopAnswerScore,
       coalesce(uba.GoldBadges,0) as GoldBadges,
       coalesce(uba.SilverBadges,0) as SilverBadges,
       coalesce(uba.BronzeBadges,0) as BronzeBadges,
       dups.DuplicateOfId,
       dups.LinkTypeName as DuplicateLinkType,
       cws.CommentAuthor,
       cws.UserStatus,
       cws.Text as SampleComment,
       qce.CloseCount,
       coalesce(array_to_string(qce.CloseReasons, ', '), 'None') as CloseReasons,
       rank() over (order by rhq.Score desc, rhq.ViewCount desc) as QuestionRank,
       count(*) over () as TotalQuestionsConsidered,
       case 
         when rhq.ViewCount = 0 then null
         else round(cast(rhq.Score as numeric)/rhq.ViewCount, 5)
       end as ScorePerView,
       substring(rhq.Title from 1 for 10) || '...' as ShortTitle
from RecentHighScoreQuestions rhq
left join TopAcceptedAnswers tpa on tpa.ParentId = rhq.Id and tpa.dr = 1
left join UserBadgeAggregates uba on uba.UserId = rhq.OwnerUserId
left join DuplicateQuestions dups on dups.Id = rhq.Id
left join lateral (
    select ccs.CommentAuthor, ccs.UserStatus, ccs.Text
    from CommentsWithUserStatus ccs
    where ccs.PostId = rhq.Id
      and ccs.Score = (
            select max(sub.Score)
            from Comments sub
            where sub.PostId = rhq.Id
          )
    limit 1
) cws on true
left join QuestionCloseEvents qce on qce.PostId = rhq.Id
where rhq.rn <= 10
union
select rhq.Id,
       rhq.Title,
       rhq.CreationDate,
       rhq.Score,
       rhq.ViewCount,
       rhq.OwnerName,
       null as TopAnswerId,
       null as TopAnswerScore,
       0 as GoldBadges,
       0 as SilverBadges,
       0 as BronzeBadges,
       null as DuplicateOfId,
       null as DuplicateLinkType,
       null as CommentAuthor,
       null as UserStatus,
       null as SampleComment,
       null as CloseCount,
       null as CloseReasons,
       null as QuestionRank,
       null as TotalQuestionsConsidered,
       null as ScorePerView,
       null as ShortTitle
from RecentHighScoreQuestions rhq
where rhq.rn = 11
order by QuestionRank, TopAnswerScore desc nulls last;