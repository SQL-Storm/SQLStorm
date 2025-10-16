-- {"query": "19.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1771} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsers as (
    select * from RecursiveUserActivity where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.LastActivityDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        -- Extract first tag from Tags string, which is in format '<tag1><tag2><tag3>'
        substring(p.Tags from '<([^>]+)>') as FirstTag
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.Score > 0 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PositiveScorePostsLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
HighActivityUsers as (
    select distinct UserId from UserActivityWindow where PostsLast30Days >= 10 and PositiveScorePostsLast30Days >= 5
),
ComplexPostSelection as (
    select
        pd.*,
        ab.GoldBadges,
        ab.SilverBadges,
        ab.BronzeBadges,
        ab.TotalBadges,
        as1.TotalAnswers,
        as1.AvgAnswerScore,
        as1.MaxAnswerScore,
        as1.MinAnswerScore,
        qcr.CloseReasonName,
        case 
            when pd.ClosedDate is not null then 'Closed'
            else 'Open'
        end as PostStatus,
        case 
            when pd.Score >= 10 then 'HighScore'
            when pd.Score between 5 and 9 then 'MediumScore'
            else 'LowScore'
        end as ScoreCategory,
        case 
            when pd.Tags is null or pd.Tags = '' then 'NoTags'
            else 'HasTags'
        end as TagPresence,
        -- String manipulation: concatenate OwnerDisplayName with first tag and post type
        concat(coalesce(pd.OwnerDisplayName, 'Anonymous'), ' | ', coalesce(pd.FirstTag, 'NoTag'), ' | ', pd.PostTypeName) as OwnerTagPostType,
        -- Complex predicate: posts with score > average score of user's posts
        (pd.Score > (
            select avg(p2.Score) from Posts p2 where p2.OwnerUserId = pd.OwnerUserId and p2.Score is not null
        )) as AboveUserAvgScore
    from PostDetails pd
    left join UserBadgeSummary ab on ab.UserId = pd.OwnerUserId
    left join AnswerStats as1 on as1.QuestionId = pd.Id
    left join QuestionCloseReasons qcr on qcr.PostId = pd.Id
    where pd.OwnerUserId in (select UserId from HighActivityUsers)
)
select
    cps.PostId,
    cps.Title,
    cps.PostTypeName,
    cps.CreationDate,
    cps.Score,
    cps.ViewCount,
    cps.AnswerCount,
    cps.CommentCount,
    cps.FavoriteCount,
    cps.OwnerUserId,
    cps.OwnerDisplayName,
    cps.GoldBadges,
    cps.SilverBadges,
    cps.BronzeBadges,
    cps.TotalBadges,
    cps.TotalAnswers,
    cps.AvgAnswerScore,
    cps.MaxAnswerScore,
    cps.MinAnswerScore,
    cps.CloseReasonName,
    cps.PostStatus,
    cps.ScoreCategory,
    cps.TagPresence,
    cps.OwnerTagPostType,
    cps.AboveUserAvgScore,
    row_number() over (partition by cps.OwnerUserId order by cps.Score desc, cps.CreationDate desc) as UserPostRank
from ComplexPostSelection cps
where cps.UserPostRank <= 5
order by cps.Score desc nulls last, cps.CreationDate desc
union
select
    p.Id,
    p.Title,
    pt.Name,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    u.DisplayName,
    0,0,0,0,
    0, null, null, null,
    null,
    case when p.ClosedDate is not null then 'Closed' else 'Open' end,
    case when p.Score >= 10 then 'HighScore' when p.Score between 5 and 9 then 'MediumScore' else 'LowScore' end,
    case when p.Tags is null or p.Tags = '' then 'NoTags' else 'HasTags' end,
    concat(coalesce(u.DisplayName, 'Anonymous'), ' | ', substring(p.Tags from '<([^>]+)>'), ' | ', pt.Name),
    false,
    9999999
from Posts p
join PostTypes pt on pt.Id = p.PostTypeId
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.Score < 0
  and p.ClosedDate is null
order by Score desc nulls last, CreationDate desc
limit 50;