with recursive TagHierarchy as (
    select
        Id,
        TagName,
        Count,
        WikiPostId,
        1 as Level,
        cast(TagName as varchar(350)) as Path
    from Tags
    where Id = (select min(Id) from Tags)
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        th.Level + 1,
        cast(th.Path || '->' || t.TagName as varchar(350))
    from Tags t
    join TagHierarchy th on t.Id = th.Id + 1
    where th.Level < 20
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(distinct c.UserId) from Comments c where c.PostId = p.Id) as UniqueCommenters,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1
),
AnswerWithQuestionInfo as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        q.OwnerUserId as QuestionOwnerUserId,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore
    from Posts a
    inner join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
),
TopAnswerers as (
    select
        AnswerOwnerUserId,
        count(*) as AnswerCount,
        avg(AnswerScore) as AvgAnswerScore,
        max(AnswerScore) as MaxAnswerScore,
        min(AnswerScore) as MinAnswerScore,
        sum(case when AnswerScore >= 10 then 1 else 0 end) as HighScoreAnswers
    from AnswerWithQuestionInfo
    group by AnswerOwnerUserId
),
PostLinkAgg as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as LinkedPostsCount,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkTypeLinked,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as LinkTypeDuplicate
    from PostLinks pl
    group by pl.PostId
),
QuestionWithDetails as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.FavoriteCount,
        q.UpVotes,
        q.DownVotes,
        q.UniqueCommenters,
        q.UserTopQuestionRank,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uba.TotalBadges,
        pa.AnswerCount as UserAnswerCount,
        pa.AvgAnswerScore,
        pa.HighScoreAnswers,
        pla.LinkedPostsCount,
        pla.LinkTypeLinked,
        pla.LinkTypeDuplicate,
        (select ph.CreationDate from PostHistory ph where ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10 order by ph.CreationDate asc limit 1) as FirstClosedDate,
        coalesce(q.FavoriteCount, 0) / nullif(q.ViewCount,0) as FavoriteToViewRatio,
        case
            when q.Tags is not null and position('java' in lower(q.Tags)) > 0 then 1 else 0
        end as HasJavaTag
    from QuestionStats q
    left join UserBadgeCounts uba on uba.UserId = q.OwnerUserId
    left join TopAnswerers pa on pa.AnswerOwnerUserId = q.OwnerUserId
    left join PostLinkAgg pla on pla.PostId = q.QuestionId
)
select distinct
    qwd.QuestionId,
    qwd.Title,
    coalesce(u.DisplayName, 'Community') as OwnerDisplayName,
    qwd.CreationDate,
    qwd.Score,
    qwd.ViewCount,
    qwd.AnswerCount,
    qwd.FavoriteCount,
    qwd.GoldBadges,
    qwd.SilverBadges,
    qwd.BronzeBadges,
    qwd.TotalBadges,
    qwd.UserAnswerCount,
    qwd.AvgAnswerScore,
    qwd.HighScoreAnswers,
    qwd.LinkedPostsCount,
    qwd.LinkTypeLinked,
    qwd.LinkTypeDuplicate,
    qwd.FirstClosedDate,
    qwd.FavoriteToViewRatio,
    qwd.HasJavaTag,
    dense_rank() over (order by qwd.Score desc) as ScoreRank,
    dense_rank() over (order by qwd.ViewCount desc) as ViewCountRank,
    case when qwd.FirstClosedDate is not null then 'Closed' else 'Open' end as PostStatus,
    coalesce(substr(coalesce(qwd.Title,'No Title'), 1, 30), 'No Title') || '...' as TitleSummary
from QuestionWithDetails qwd
left join Users u on u.Id = qwd.OwnerUserId
where qwd.AnswerCount > 5
  and qwd.Score > 10
  and (qwd.HasJavaTag = 1 or qwd.FavoriteToViewRatio > 0.001)
order by ScoreRank
limit 100;