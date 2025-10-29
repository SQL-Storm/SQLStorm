with RankedAnswers as (
    select 
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (
            partition by p.ParentId
            order by p.Score desc, p.CreationDate asc
        ) as AnswerRank
    from Posts p
    inner join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2
),
QuestionDetails as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        u.DisplayName as QuestionOwner,
        q.CreationDate as QuestionCreated,
        coalesce(q.AcceptedAnswerId, -1) as AcceptedAnswerId
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
AnswerDetails as (
    select 
        ra.Id as AnswerId,
        ra.ParentId as QuestionId,
        ra.Score as AnswerScore,
        ra.CreationDate as AnswerCreated,
        ra.OwnerUserId as AnswerOwnerId,
        ra.OwnerName as AnswerOwnerName,
        ra.AnswerRank
    from RankedAnswers ra
),
AnswerCommentsCount as (
    select 
        a.Id as AnswerId,
        count(c.Id) filter (where c.UserId is not null) as CommentedUsersCount,
        count(c.Id) filter (where c.UserId is null) as AnonymousCommentsCount
    from Posts a
    left join Comments c on a.Id = c.PostId
    where a.PostTypeId = 2
    group by a.Id
),
TopAnswerComments as (
    select 
        adc.AnswerId,
        adc.CommentedUsersCount,
        adc.AnonymousCommentsCount,
        acmax.MaxScore
    from AnswerCommentsCount adc
    inner join (
        select 
            c.PostId,
            max(c.Score) as MaxScore
        from Comments c
        group by c.PostId
    ) acmax on adc.AnswerId = acmax.PostId
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
QuestionAnswerStats as (
    select 
        q.QuestionId,
        q.Title,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.QuestionOwner,
        q.QuestionCreated,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerCreated,
        a.AnswerOwnerId,
        a.AnswerOwnerName,
        a.AnswerRank,
        coalesce(tac.CommentedUsersCount, 0) as CommentedUsersCount,
        coalesce(tac.AnonymousCommentsCount, 0) as AnonymousCommentsCount,
        coalesce(tac.MaxScore, 0) as MaxCommentScore,
        coalesce(ubc.GoldBadges, 0) as GoldBadges,
        coalesce(ubc.SilverBadges, 0) as SilverBadges,
        coalesce(ubc.BronzeBadges, 0) as BronzeBadges
    from QuestionDetails q
    left join AnswerDetails a on q.QuestionId = a.QuestionId and a.AnswerRank <= 3
    left join TopAnswerComments tac on a.AnswerId = tac.AnswerId
    left join UserBadgeCounts ubc on a.AnswerOwnerId = ubc.UserId
    where q.AcceptedAnswerId IS NOT NULL
),
FilteredQuestions as (
    select 
        qas.*
    from QuestionAnswerStats qas
    where qas.ViewCount > 1000
      and (qas.Tags like '%<sql>%' or qas.Tags like '%<postgresql>%')
      and qas.QuestionScore > 0
      and qas.AnswerScore > 0
),
BadgeFilteredUsers as (
    select UserId
    from UserBadgeCounts
    where GoldBadges + SilverBadges + BronzeBadges >= 3
),
FinalSelection as (
    select distinct
        fq.QuestionId,
        fq.Title,
        fq.QuestionScore,
        fq.ViewCount,
        fq.Tags,
        fq.QuestionOwner,
        fq.QuestionCreated,
        fq.AnswerId,
        fq.AnswerScore,
        fq.AnswerCreated,
        fq.AnswerOwnerId,
        fq.AnswerOwnerName,
        fq.AnswerRank,
        fq.CommentedUsersCount,
        fq.AnonymousCommentsCount,
        fq.MaxCommentScore,
        fq.GoldBadges,
        fq.SilverBadges,
        fq.BronzeBadges
    from FilteredQuestions fq
    inner join BadgeFilteredUsers bfu on fq.AnswerOwnerId = bfu.UserId
)
select 
    fs.QuestionId,
    fs.Title as QuestionTitle,
    length(fs.Title) as TitleLength,
    fs.QuestionScore,
    fs.ViewCount,
    fs.Tags,
    fs.QuestionOwner,
    extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - fs.QuestionCreated))/86400 as DaysSinceQuestionPosted,
    fs.AnswerId,
    fs.AnswerScore,
    extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - fs.AnswerCreated))/86400 as DaysSinceAnswerPosted,
    fs.AnswerOwnerName,
    fs.AnswerRank,
    fs.CommentedUsersCount,
    fs.AnonymousCommentsCount,
    fs.MaxCommentScore,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    case 
        when fs.CommentedUsersCount > 10 then 'High Engagement'
        when fs.CommentedUsersCount between 1 and 10 then 'Moderate Engagement'
        else 'Low Engagement'
    end as EngagementLevel,
    regexp_replace(fs.Tags, '[<>]', '', 'g') as CleanTags,
    -- replace initcap with standard SQL: capitalize first letter of each word
    concat(
      upper(substr(fs.AnswerOwnerName,1,1)),
      lower(substr(fs.AnswerOwnerName,2))
    ) as AnswerOwnerProperName
from FinalSelection fs
group by
    fs.QuestionId,
    fs.Title,
    fs.QuestionScore,
    fs.ViewCount,
    fs.Tags,
    fs.QuestionOwner,
    fs.QuestionCreated,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerCreated,
    fs.AnswerOwnerName,
    fs.AnswerRank,
    fs.CommentedUsersCount,
    fs.AnonymousCommentsCount,
    fs.MaxCommentScore,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges
order by fs.QuestionScore desc, fs.ViewCount desc, fs.AnswerScore desc
limit 100;