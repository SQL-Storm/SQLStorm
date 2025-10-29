-- {"query": "2928.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1453} 
with UserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        coalesce(sum(bd.Score),0) as BadgeScore,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as BadgeRecencyRank
    from Users u
    left join Badges b on b.UserId = u.Id
    left join (
        select b1.Id, (case b1.Class when 1 then 5 when 2 then 3 when 3 then 1 else 0 end) * count(distinct p.Id) as Score
        from Badges b1
        join Posts p on p.OwnerUserId = b1.UserId
        where p.PostTypeId = 1 and b1.Date >= p.CreationDate
        group by b1.Id, b1.Class
    ) bd on bd.Id = b.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate as QuestionCreated,
        count(a.Id) filter (where a.CreationDate <= p.LastActivityDate) as AnswerCount,
        coalesce(avg(a.Score), 0) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score > p.Score then 1 else 0 end) as AnswersBetterThanQuestion,
        p.Score as QuestionScore
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(case when p.PostTypeId=1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as QuestionsLast30Days,
        sum(case when p.PostTypeId=2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as AnswersLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinksCTE as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate, pl.LinkTypeId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        row_number() over (partition by pl.PostId order by pl.CreationDate desc) as rn
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
FilteredDuplicates as (
    select * from DuplicateLinksCTE where rn = 1
),
QuestionCloseReasons as (
    select ph.PostId, crt.Name as CloseReasonName, max(ph.CreationDate) as LastClosed
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
ComplexFilteredUsers as (
    select ub.UserId, ub.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.BadgeScore,
           max(qas.AnswerCount) as MaxAnswerCountForUser,
           max(qas.AvgAnswerScore) as MaxAvgAnswerScoreForUser,
           max(uaw.PostsLast30Days) as RecentActivityCount
    from UserBadges ub
    left join QuestionAnswerStats qas on qas.OwnerUserId = ub.UserId
    left join UserActivityWindow uaw on uaw.UserId = ub.UserId
    group by ub.UserId, ub.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.BadgeScore
    having coalesce(max(uaw.PostsLast30Days),0) > 10 and (ub.GoldBadges + ub.SilverBadges + ub.BronzeBadges) > 5
),
FinalPostsStats as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(cfr.CloseReasonName, 'Open') as CloseStatus,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRankForUser,
        case 
            when p.Tags is null then array[]::text[]
            else string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') 
        end as TagArray,
        case when p.AcceptedAnswerId is null then false else true end as IsAccepted
    from Posts p
    left join QuestionCloseReasons cfr on cfr.PostId = p.Id
    where p.PostTypeId = 1
)
select distinct
    fps.Id as QuestionId,
    fps.Title,
    fps.CreationDate,
    fps.Score,
    fps.ViewCount,
    fps.CloseStatus,
    fps.IsAccepted,
    array_to_string(fps.TagArray, ',') as Tags,
    cfus.DisplayName as OwnerName,
    cfus.GoldBadges,
    cfus.SilverBadges,
    cfus.BronzeBadges,
    cfus.BadgeScore,
    cfus.RecentActivityCount,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.AnswersBetterThanQuestion,
    fd.RelatedPostId as DuplicateOfId,
    fd.RelatedPostTitle as DuplicateOfTitle
from FinalPostsStats fps
join ComplexFilteredUsers cfus on cfus.UserId = (select coalesce(fps.OwnerUserId, -1))
left join QuestionAnswerStats qas on qas.QuestionId = fps.Id
left join FilteredDuplicates fd on fd.PostId = fps.Id
where fps.ScoreRankForUser <= 3
order by fps.CreationDate desc, fps.Score desc
limit 100;