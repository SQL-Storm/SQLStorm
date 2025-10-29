with recursive TagHierarchy as (
    select Id, TagName, ExcerptPostId, WikiPostId, IsModeratorOnly, IsRequired, 1 as Level
    from Tags
    where IsRequired = true

    union all

    select t.Id, t.TagName, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, th.Level + 1
    from Tags t
    inner join TagHierarchy th on t.Id = th.Id + 1 and t.IsRequired = true and th.Level < 3
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as MostRecentBadgeDate,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopPostsCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        pb.GoldBadges,
        pb.SilverBadges,
        pb.BronzeBadges,
        pb.TagBasedBadges
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join UserBadgeCounts pb on a.OwnerUserId = pb.UserId
    where q.PostTypeId = 1 and q.ClosedDate is null and q.Score > 5
),
CommentAggregates as (
    select
        c.PostId,
        count(*) as TotalComments,
        sum(c.Score) as SumCommentScore,
        max(c.CreationDate) as LastCommentDate,
        bool_or(c.Text ilike '%bug%') as ContainsBugKeyword
    from Comments c
    group by c.PostId
),
LatestEditPerPost AS (
    select ph.PostId, ph.Id as EditId, ph.CreationDate as EditDate, ph.UserId, ph.Comment as EditComment
    from (
      select ph.*,
             row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
      from PostHistory ph
      where ph.PostHistoryTypeId in (4,5,6)
    ) ph
    where ph.rn = 1
),
DuplicatesWithLinks AS (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    where pl.LinkTypeId = 3
),
ScoreWindow AS (
    select
        p.Id,
        p.PostTypeId,
        p.Score,
        avg(p.Score) over (partition by p.PostTypeId) as AvgScoreByPostType,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
)
select
    p.Id as PostId,
    p.Title,
    coalesce(nullif(p.Tags, ''), '<none>') as Tags,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    u.DisplayName as OwnerDisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TagBasedBadges,
    ca.TotalComments,
    ca.SumCommentScore,
    ca.LastCommentDate,
    ca.ContainsBugKeyword,
    coalesce(ph.EditId, -1) as LatestEditId,
    ph.EditDate as LatestEditDate,
    ph.UserId as LatestEditorUserId,
    ph.EditComment as LatestEditComment,
    dup.RelatedPostId as DuplicateOf,
    dup.LinkTypeName as DuplicateLinkType,
    sw.AvgScoreByPostType,
    sw.ScoreRank,
    CAST((p.Score * 1.0) / greatest(nullif(p.ViewCount,0), 1) AS numeric(10,5)) as ScorePerView,
    case when p.ClosedDate is not null then 'Closed' else 'Open' end as PostStatus,
    pwa.AnswerId,
    pwa.AnswerScore,
    coalesce(pb.DisplayName, '<no owner>') as AnswerOwner,
    pb.GoldBadges as AnswerOwnerGoldBadges,
    pb.SilverBadges as AnswerOwnerSilverBadges,
    pb.BronzeBadges as AnswerOwnerBronzeBadges,
    pb.TagBasedBadges as AnswerOwnerTagBasedBadges,
    pwa.AnswerCreationDate
from Posts p
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeCounts ubc on u.Id = ubc.UserId
left join CommentAggregates ca on p.Id = ca.PostId
left join LatestEditPerPost ph on p.Id = ph.PostId
left join DuplicatesWithLinks dup on p.Id = dup.PostId
left join ScoreWindow sw on p.Id = sw.Id
left join PostWithAnswers pwa on p.Id = pwa.QuestionId
left join UserBadgeCounts pb on pwa.AnswerOwnerUserId = pb.UserId
where p.PostTypeId in (1, 2)
  and (p.Score > 10 or (ca.TotalComments is not null and ca.TotalComments > 5))
order by sw.ScoreRank, p.ViewCount desc
limit 100;