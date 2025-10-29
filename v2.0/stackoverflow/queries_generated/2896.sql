-- {"query": "2896.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1907} 
with RecentHighScoreAnswers as (
    select a.Id, a.ParentId, a.Score, a.ViewCount,
        row_number() over (partition by a.ParentId order by a.Score desc, a.ViewCount desc) as rn
    from Posts a
    where a.PostTypeId = 2
      and a.CreationDate > now() - interval '180 days'
      and a.Score > 5
),
UserBadgesAgg as (
    select b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        string_agg(distinct b.Name, ', ') filter (where b.TagBased = 0) as UniqueBadges,
        bool_or(b.TagBased = 1) as HasTagBasedBadges
    from Badges b
    group by b.UserId
),
QuestionAnswerStats as (
    select q.Id as QuestionId, q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        coalesce(r.Score, 0) as TopAnswerScore,
        coalesce(r.Id, -1) as TopAnswerId,
        coalesce(r.ViewCount, 0) as TopAnswerViews,
        (select count(*) from Posts a2 where a2.ParentId = q.Id and a2.Score > q.Score) as AnswersBetterScoreThanQ,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed,
        (select count(distinct ph.PostHistoryTypeId) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId in (10,11)) as CloseReopenEdits
    from Posts q
    left join RecentHighScoreAnswers r on r.ParentId = q.Id and r.rn = 1
    where q.PostTypeId = 1
      and q.CreationDate > now() - interval '1 year'
),
UserActivityWindows as (
    select u.Id,
        u.DisplayName,
        u.Reputation,
        array_length(string_to_array(u.Location, ','), 1) as LocationParts,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as AnswersPosted,
        max(p.Score) filter (where p.PostTypeId = 1) over (partition by u.Id) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) over (partition by u.Id) as MaxAnswerScore,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        b.HasTagBasedBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > u.CreationDate and p.CreationDate <= now()
    left join UserBadgesAgg b on b.UserId = u.Id
    where u.Reputation > 1000
),
DuplicatesAndLinks as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        case when pl.LinkTypeId = 3 then 1 else 0 end as IsDuplicateLink
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.CreationDate > now() - interval '2 years'
),
TopUsersActivity as (
    select u.Id, u.DisplayName,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 10000
    group by u.Id, u.DisplayName
), CrossTypePosts as (
    select p1.Id as PostId1, p1.PostTypeId as PostType1,
           p2.Id as PostId2, p2.PostTypeId as PostType2,
           p1.Score + p2.Score as CombinedScore
    from Posts p1
    inner join Posts p2 on p1.OwnerUserId = p2.OwnerUserId and p1.Id <> p2.Id
    where p1.PostTypeId = 1 and p2.PostTypeId = 2
      and p1.Score > 0 and p2.Score > 0
), CloseReasonCounts as (
    select crt.Name as CloseReasonName,
        count(ph.Id) as CloseEvents,
        avg(extract(epoch from (now() - ph.CreationDate))/3600) as AvgCloseAgeHours
    from CloseReasonTypes crt
    left join PostHistory ph on ph.PostHistoryTypeId = 10 and ph.Comment = cast(crt.Id as varchar)
    group by crt.Name
)
select 
    qas.QuestionId,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.TopAnswerId,
    qas.TopAnswerScore,
    qas.TopAnswerViews,
    qas.AnswersBetterScoreThanQ,
    qas.IsClosed,
    qas.CloseReopenEdits,
    ua.DisplayName as QuestionOwner,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.HasTagBasedBadges,
    dup.IsDuplicateLink,
    dup.LinkTypeName,
    dup.RelatedPostTitle,
    tuc.TotalPostScore as OwnerTotalScore,
    tuc.QuestionsCount as OwnerQuestions,
    tuc.AnswersCount as OwnerAnswers,
    tuc.AvgAnswerScore as OwnerAvgAnswerScore,
    crc.CloseReasonName,
    crc.CloseEvents,
    round(crc.AvgCloseAgeHours,2) as AvgCloseAgeHours,
    uact.LocationParts,
    uact.MaxQuestionScore,
    uact.MaxAnswerScore,
    uact.QuestionsAsked,
    uact.AnswersPosted
from QuestionAnswerStats qas
inner join Users ua on ua.Id = qas.OwnerUserId
left join DuplicatesAndLinks dup on dup.PostId = qas.QuestionId and dup.IsDuplicateLink = 1
left join TopUsersActivity tuc on tuc.Id = ua.Id
left join CloseReasonCounts crc on crc.CloseReasonName = (select crt.Name from CloseReasonTypes crt join PostHistory ph on ph.PostHistoryTypeId=10 and ph.Comment = cast(crt.Id as varchar) and ph.PostId = qas.QuestionId limit 1)
left join UserActivityWindows uact on uact.Id = ua.Id
where qas.QuestionScore > 10
  and (uq.totalpostscore is null or tuc.TotalPostScore > 500)
union
select 
    c.PostId as QuestionId,
    max(p.Score) as QuestionScore,
    max(p.ViewCount) as QuestionViews,
    -1 as TopAnswerId,
    0 as TopAnswerScore,
    0 as TopAnswerViews,
    0 as AnswersBetterScoreThanQ,
    0 as IsClosed,
    0 as CloseReopenEdits,
    'Anonymous' as QuestionOwner,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    false as HasTagBasedBadges,
    0 as IsDuplicateLink,
    null as LinkTypeName,
    null as RelatedPostTitle,
    0 as OwnerTotalScore,
    0 as OwnerQuestions,
    0 as OwnerAnswers,
    0 as OwnerAvgAnswerScore,
    null as CloseReasonName,
    0 as CloseEvents,
    0 as AvgCloseAgeHours,
    0 as LocationParts,
    0 as MaxQuestionScore,
    0 as MaxAnswerScore,
    0 as QuestionsAsked,
    0 as AnswersPosted
from Comments c
inner join Posts p on p.Id = c.PostId and p.PostTypeId = 1
where c.CreationDate > now() - interval '7 days'
group by c.PostId
order by QuestionScore desc, TopAnswerScore desc, OwnerTotalScore desc
limit 50;