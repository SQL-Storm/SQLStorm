-- {"query": "577.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1469} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(ac.CommentCount, 0) as CommentCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on p.Id = a.ParentId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) ac on p.Id = ac.PostId
    where p.PostTypeId in (1,2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct ph.Id) as TotalEdits,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswers as (
    select
        QuestionId,
        Title,
        Tags,
        QuestionScore,
        ViewCount,
        OwnerUserId,
        AnswerId,
        AnswerScore,
        AnswerOwnerUserId,
        AnswerCreationDate
    from QuestionsWithAnswers
    where AnswerRank = 1
),
UserReputationWindow as (
    select
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        sum(Reputation) over (order by CreationDate rows between unbounded preceding and current row) as CumulativeReputation
    from Users
    where Reputation is not null
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    join Posts p on ph.PostId = p.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserBadgesSummary as (
    select
        UserId,
        count(case when Class = 1 then 1 end) as GoldBadges,
        count(case when Class = 2 then 1 end) as SilverBadges,
        count(case when Class = 3 then 1 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges
    group by UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    urw.Reputation,
    urw.CreumulativeReputation,
    ua.TotalPosts,
    ua.TotalEdits,
    ua.TotalUpVotesGiven,
    ua.TotalDownVotesGiven,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    ps.PostId,
    ps.Title as PostTitle,
    ps.Score as PostScore,
    ps.ViewCount as PostViews,
    ps.AnswerCount,
    ps.CommentCount,
    ps.IsClosed,
    tq.AnswerId as TopAnswerId,
    tq.AnswerScore as TopAnswerScore,
    dq.RelatedPostId as DuplicateOfPostId,
    dq.LinkTypeName as DuplicateLinkType,
    cqr.CloseReasonName,
    case
        when u.Location is null then 'Location Unknown'
        else 'Located in ' || u.Location
    end as UserLocationDescription,
    case
        when u.WebsiteUrl is null or u.WebsiteUrl = '' then 'No Website'
        else 'Website: ' || u.WebsiteUrl
    end as UserWebsiteDescription
from Users u
left join UserReputationWindow urw on u.Id = urw.Id
left join UserActivity ua on u.Id = ua.UserId
left join UserBadgesSummary bs on u.Id = bs.UserId
left join PostStats ps on u.Id = ps.OwnerUserId and ps.UserPostRank = 1
left join TopAnswers tq on ps.PostId = tq.QuestionId
left join DuplicateLinks dq on ps.PostId = dq.PostId
left join ClosedQuestionsWithReasons cqr on ps.PostId = cqr.PostId
where u.Reputation > 5000
  and (ps.IsClosed = 0 or ps.IsClosed is null)
  and exists (
      select 1
      from Posts p2
      where p2.OwnerUserId = u.Id
        and p2.PostTypeId = 1
        and p2.Score > 10
  )
order by urw.CreumulativeReputation desc, ua.TotalPosts desc
limit 100;