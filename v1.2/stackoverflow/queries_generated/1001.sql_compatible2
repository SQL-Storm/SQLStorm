with RecursiveBadges as (
    select 
          u.Id as UserId
        , u.DisplayName
        , b.Name as BadgeName
        , b.Class
        , b.Date
        , row_number() over (partition by u.Id order by b.Date desc, b.Class asc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id and b.Name is not null
    where u.Reputation > 1000
)
, LatestUserBadge as (
    select UserId, BadgeName, Class, Date
    from RecursiveBadges
    where BadgeRank = 1
)
, PostWithAnswers as (
    select 
          q.Id as QuestionId
        , q.Title
        , q.CreationDate as QuestionCreation
        , a.Id as AnswerId
        , a.Score as AnswerScore
        , a.CreationDate as AnswerCreation
        , u.Id as AnswererUserId
        , u.DisplayName as AnswererDisplayName
        , u.Reputation as AnswererReputation
        , dense_rank() over (partition by q.Id order by a.Score desc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
        and q.AcceptedAnswerId is not null
)
, PostCommentsCount as (
    select 
          p.Id as PostId
        , count(c.Id) as CommentCount
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
)
, ComplexFilteredPosts as (
    select 
          p.Id
        , p.Title
        , p.Tags
        , p.Score
        , p.ViewCount
        , coalesce(pc.CommentCount,0) as CommentCount
        , p.AcceptedAnswerId
        , u.DisplayName as OwnerName
        , u.Reputation as OwnerReputation
        , case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
          end as PostStatus
        , row_number() over (partition by u.Id order by p.CreationDate desc) as UserPostRank
        , p.CreationDate as CreationDate
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostCommentsCount pc on pc.PostId = p.Id
    where p.PostTypeId = 1
        and p.Score > 0
        and (lower(p.Tags) like '%<sql>%' or lower(p.Tags) like '%<database>%')
        and (p.ClosedDate is null or p.ClosedDate > DATE '2024-10-01' - INTERVAL '180' DAY)
        and exists (
            select 1 from Votes v
            where v.PostId = p.Id
                and v.VoteTypeId = 2
                and v.CreationDate > p.CreationDate - INTERVAL '60' DAY
        )
)
select distinct 
      cf.Title
    , cf.OwnerName
    , cf.OwnerReputation
    , cf.ViewCount
    , cf.Score
    , cf.CommentCount
    , cf.PostStatus
    , cf.Tags
    , la.BadgeName as LatestBadge
    , pw.AnswerScore
    , pw.AnswererDisplayName
    , pw.AnswererReputation
    , phc.PostHistoryTypeName
    , ph.CreateDateLastEdit
    , case when ph.CreateDateLastEdit < cf.CreationDate + INTERVAL '7' DAY then 'Recently Edited' else 'Not Recently Edited' end as EditStatus
from ComplexFilteredPosts cf
left join LatestUserBadge la on la.UserId = (
    select OwnerUserId from Posts where Id = cf.Id
)
left join PostWithAnswers pw on pw.QuestionId = cf.Id and pw.AnswerRank = 1
left join (
    select 
          pht.Id as PostHistoryTypeId
        , pht.Name as PostHistoryTypeName
    from PostHistoryTypes pht
) phc on 1=1
left join lateral (
    select max(ph.CreationDate) as CreateDateLastEdit
    from PostHistory ph
    where ph.PostId = cf.Id 
      and ph.PostHistoryTypeId in (4,5,6)
) ph on true
where cf.UserPostRank <= 5

union

select 
      'Sum of All' as Title
    , cast(null as text) as OwnerName
    , cast(null as integer) as OwnerReputation
    , sum(cf.ViewCount) as ViewCount
    , sum(cf.Score) as Score
    , sum(cf.CommentCount) as CommentCount
    , cast(null as text) as PostStatus
    , cast(null as text) as Tags
    , cast(null as text) as LatestBadge
    , cast(null as integer) as AnswerScore
    , cast(null as text) as AnswererDisplayName
    , cast(null as integer) as AnswererReputation
    , cast(null as text) as PostHistoryTypeName
    , cast(null as timestamp) as CreateDateLastEdit
    , cast(null as text) as EditStatus
from ComplexFilteredPosts cf
order by OwnerReputation desc, Score desc, Title asc;