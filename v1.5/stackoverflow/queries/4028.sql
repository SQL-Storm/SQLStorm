with RecursiveTagStats as (
    select
        t.Id as TagId,
        t.TagName,
        p.Id as QuestionId,
        p.Score as QuestionScore,
        p.ViewCount,
        u.Id as OwnerUserId,
        u.Reputation as OwnerReputation,
        avg(case when c.Score is null then 0 else c.Score end) over (partition by p.Id) as AvgCommentScore,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p
        on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u
        on p.OwnerUserId = u.Id
    left join Comments c
        on c.PostId = p.Id
),
TopQuestionsPerTag as (
    select
        TagId,
        TagName,
        QuestionId,
        QuestionScore,
        ViewCount,
        OwnerUserId,
        OwnerReputation,
        AvgCommentScore
    from RecursiveTagStats
    where rn <= 5
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        sum(case when a.CreationDate > (q.CreationDate + interval '1 day') then 1 else 0 end) as AnswersAfterFirstDay
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.ParentId
),
UserBadgeAggregates as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostLinkDupCount as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserActivityWindows as (
    select
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1 and p.CreationDate >= u.CreationDate) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2 and p.CreationDate >= u.CreationDate) as AnswersPosted,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        count(b.Id) as BadgeCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
),
HighlyActiveUsers as (
    select
        Id,
        DisplayName,
        QuestionsPosted,
        AnswersPosted,
        BadgeCount,
        MaxPostScore,
        AvgPostScore,
        row_number() over (order by QuestionsPosted desc, AnswersPosted desc, BadgeCount desc) as rn
    from UserActivityWindows
    where QuestionsPosted > 50 and AnswersPosted > 100
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseReasonCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    group by ph.PostId, crt.Name
),
QuestionsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        crc.CloseReason,
        crc.CloseReasonCount
    from Posts p
    left join CloseReasonCounts crc on p.Id = crc.PostId
    where p.PostTypeId = 1
)
select
    tq.TagName,
    tq.QuestionId,
    tq.QuestionScore,
    tq.ViewCount,
    tq.OwnerUserId,
    coalesce(uba.GoldBadges,0) as OwnerGoldBadges,
    coalesce(uba.SilverBadges,0) as OwnerSilverBadges,
    coalesce(uba.BronzeBadges,0) as OwnerBronzeBadges,
    coalesce(a.AnswerCount,0) as AnswerCount,
    coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(a.AnswersAfterFirstDay,0) as AnswersAfterFirstDay,
    coalesce(pldc.DuplicateLinksCount,0) as DuplicateLinksToQuestion,
    tq.AvgCommentScore,
    ha.DisplayName as OwnerName,
    ha.QuestionsPosted as OwnerQuestionsPosted,
    ha.AnswersPosted as OwnerAnswersPosted,
    ha.BadgeCount as OwnerBadgesTotal,
    qc.CloseReason,
    qc.CloseReasonCount,
    concat_ws(' | ',
        'Score:', tq.QuestionScore,
        'Views:', tq.ViewCount,
        'Answers:', coalesce(a.AnswerCount,0),
        'Owner Rep:', coalesce(hu.Reputation,0),
        'Owner Gold Badges:', coalesce(uba.GoldBadges,0)
    ) as SummaryInfo
from TopQuestionsPerTag tq
left join AnswerStats a on a.QuestionId = tq.QuestionId
left join UserBadgeAggregates uba on uba.UserId = tq.OwnerUserId
left join PostLinkDupCount pldc on pldc.PostId = tq.QuestionId
left join Users hu on hu.Id = tq.OwnerUserId
left join HighlyActiveUsers ha on ha.Id = tq.OwnerUserId
left join QuestionsWithCloseInfo qc on qc.Id = tq.QuestionId
where (tq.QuestionScore > 10 or coalesce(a.AnswerCount,0) > 5)
  and (ha.rn is null or ha.rn <= 100)
order by tq.TagName, tq.QuestionScore desc, tq.ViewCount desc;