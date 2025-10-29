with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
), LatestBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where rn <= 3
), PostScores as (
    select
        p.Id as PostId,
        p.PostTypeId,
        coalesce(p.Score, 0) as Score,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        concat_ws(' | ', 
          substring(p.Title from 1 for 50), 
          coalesce(nullif(p.Tags, ''), 'No Tags')) as TitleSnippet,
        dense_rank() over (partition by p.PostTypeId order by coalesce(p.Score,0) desc) as ScoreRank
    from Posts p
    where p.CreationDate > '2015-01-01' and p.PostTypeId in (1,2)
), AnswerCountByQuestion as (
    select 
        ParentId as QuestionId,
        count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
    group by ParentId
), UserActivityWindows as (
    select 
        u.Id as UserId,
        date_trunc('month', u.CreationDate) as UserCreationMonth,
        -- replace FILTER and windowed conditional aggregates with SUM(CASE ...)
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by u.CreationDate) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by u.CreationDate) as AnswersCount,
        sum(case when v.VoteTypeId = 2 and v.PostId = p.Id then 1 else 0 end) over (partition by u.Id order by u.CreationDate) as TotalUpVotesGiven,
        row_number() over (partition by u.Id order by u.CreationDate) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    where u.CreationDate >= '2010-01-01' and u.CreationDate <= '2020-12-31'
), UserCommentStats as (
    select 
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        bool_or(case when c.Text is null then true else false end) as HasNullComments
    from Comments c
    group by c.UserId
), ComplexPostsAnalysis as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Resolved'
            else 'Open'
        end as Status,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        coalesce(ac.AnswerCount,0) as AnswerCount,
        (select string_agg(ph.Name, ', ')
         from PostHistoryTypes ph
         join PostHistory h on h.PostHistoryTypeId = ph.Id and h.PostId = p.Id
         where h.PostHistoryTypeId in (4,5,6)
        ) as EditTypes
    from Posts p
    left join AnswerCountByQuestion ac on ac.QuestionId = p.Id
    where p.PostTypeId in (1,2)
), RankablePosts as (
    select 
        p.*,
        ntile(10) over (order by Score desc nulls last, ViewCount desc nulls last) as ScoreDecile,
        lag(Score) over (partition by p.PostTypeId order by Score desc) as PrevScore,
        lead(Score) over (partition by p.PostTypeId order by Score desc) as NextScore
    from ComplexPostsAnalysis p
), UserRecursiveLinks as (
    select 
        l.Id LinkId,
        l.PostId,
        l.RelatedPostId,
        l.LinkTypeId,
        p.OwnerUserId as PostOwner,
        rp.OwnerUserId as RelatedPostOwner,
        row_number() over (partition by l.PostId order by l.CreationDate desc) as LatestLinkSeq
    from PostLinks l
    join Posts p on p.Id = l.PostId
    join Posts rp on rp.Id = l.RelatedPostId
    where l.LinkTypeId in (1,3)
), RecursiveLinkHits as (
    select ul1.PostId, ul1.RelatedPostId, ul1.PostOwner, ul1.RelatedPostOwner,
        case when ul1.LinkTypeId = 3 then 'Duplicate' else 'Linked' end as LinkTypeName,
        ul1.LatestLinkSeq,
        count(*) over (partition by ul1.PostId) as LinksCount,
        (select count(*) from Posts p where p.ParentId = ul1.PostId) as AnswerCountFromLink,
        (select count(*) from Votes v where v.PostId = ul1.PostId and v.VoteTypeId = 2) as PostUpVotes
    from UserRecursiveLinks ul1
    where ul1.LatestLinkSeq = 1
)
select 
    up.UserId,
    up.DisplayName,
    up.BadgeName,
    up.Class as BadgeClass,
    ps.ScoreRank,
    ps.TitleSnippet,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.TotalUpVotesGiven,
    ucs.CommentCount,
    ucs.AvgCommentLength,
    cr.LinksCount,
    cr.LinkTypeName,
    rp.Status as PostStatus,
    rp.ScoreDecile,
    rp.UpVotes,
    rp.DownVotes,
    rp.AnswerCount,
    concat_ws(' / ', case when rp.EditTypes is null then 'No Edits' else rp.EditTypes end, coalesce(cast(rp.ViewCount as varchar), '0')) as EditAndViewInfo
from LatestBadges up
join PostScores ps on ps.OwnerUserId = up.UserId and ps.ScoreRank <= 5
left join UserActivityWindows ua on ua.UserId = up.UserId and ua.rn = 1
left join UserCommentStats ucs on ucs.UserId = up.UserId
left join RecursiveLinkHits cr on cr.PostOwner = up.UserId
left join RankablePosts rp on rp.Id = ps.PostId
where up.BadgeName is not null 
union
select 
    u.Id as UserId,
    u.DisplayName,
    null as BadgeName,
    null as BadgeClass,
    null as ScoreRank,
    null as TitleSnippet,
    0 as QuestionsCount,
    0 as AnswersCount,
    0 as TotalUpVotesGiven,
    0 as CommentCount,
    0 as AvgCommentLength,
    0 as LinksCount,
    null as LinkTypeName,
    'Open' as PostStatus,
    0 as ScoreDecile,
    0 as UpVotes,
    0 as DownVotes,
    0 as AnswerCount,
    'No Edits / 0' as EditAndViewInfo
from Users u
where u.Id not in (select UserId from LatestBadges)
order by UserId, ScoreRank nulls last, BadgeClass nulls last;