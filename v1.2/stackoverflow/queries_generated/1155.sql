-- {"query": "1155.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1231} 
with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, b.Class
),
UserActivity as (
    select
        p.OwnerUserId as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        avg(p.Score) filter (where p.PostTypeId in (1, 2)) as AvgPostScore,
        max(p.CreationDate) as LastPostDate,
        count(distinct c.Id) as CommentsMade
    from Posts p
    left join Comments c on c.UserId = p.OwnerUserId
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
RankedUserPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRankDesc,
        rank() over (partition by p.OwnerUserId order by p.ViewCount desc) as ViewRankDesc
    from Posts p
    where p.OwnerUserId is not null
),
QuestionAnswerPairs as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswererUserId,
        u.DisplayName as AnswererDisplayName,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts q
    left join Posts a on q.Id = a.ParentId and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
FinalOutput as (
    select
        u.Id as UserId,
        coalesce(u.DisplayName, 'Unknown') as DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        coalesce(rbcs.GoldCount,0) as GoldBadges,
        coalesce(rbcs.SilverCount,0) as SilverBadges,
        coalesce(rbcs.BronzeCount,0) as BronzeBadges,
        ua.AvgPostScore,
        rp.ScoreRankDesc,
        rp.ViewRankDesc,
        qap.QuestionTitle,
        qap.AnswerId,
        qap.AnswerScore,
        qap.IsAccepted,
        dup.PostTitle as DuplicateQuestionTitle,
        dup.RelatedPostTitle as DuplicateTargetTitle,
        case
            when u.Location is null then 'Location Unknown'
            when lower(u.Location) like '%usa%' then 'USA based'
            else 'Other Location'
        end as LocationCategory,
        substring(ua.QuestionsAsked::text || ' Qs, ' || ua.AnswersGiven::text || ' As', 1, 30) as Q_A_Summary,
        coalesce(u.WebsiteUrl, 'No Website') as WebsiteUrlNormalized
    from Users u
    left join UserActivity ua on ua.UserId = u.Id
    left join (
        select
            UserId,
            max(case when Class = 1 then BadgeCount else 0 end) as GoldCount,
            max(case when Class = 2 then BadgeCount else 0 end) as SilverCount,
            max(case when Class = 3 then BadgeCount else 0 end) as BronzeCount
        from RecursiveBadgeCounts
        group by UserId
    ) rbcs on rbcs.UserId = u.Id
    left join RankedUserPosts rp on rp.OwnerUserId = u.Id and rp.ScoreRankDesc = 1
    left join LATERAL (
        select
            min(q.QuestionTitle) as QuestionTitle,
            min(a.AnswerId) as AnswerId,
            max(a.AnswerScore) as AnswerScore,
            max(a.IsAccepted) as IsAccepted
        from QuestionAnswerPairs a
        join Posts q on q.Id = a.QuestionId
        where a.AnswererUserId = u.Id
    ) qap on true
    left join LATERAL (
        select
            min(d.PostTitle) as PostTitle,
            min(d.RelatedPostTitle) as RelatedPostTitle
        from DuplicateLinks d
        where d.PostId = qap.QuestionId
    ) dup on true
    where u.Reputation > 500
)
select
    UserId,
    DisplayName,
    QuestionsAsked,
    AnswersGiven,
    CommentsMade,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AvgPostScore,
    ScoreRankDesc,
    ViewRankDesc,
    QuestionTitle,
    AnswerId,
    AnswerScore,
    IsAccepted,
    DuplicateQuestionTitle,
    DuplicateTargetTitle,
    LocationCategory,
    Q_A_Summary,
    WebsiteUrlNormalized
from FinalOutput
order by GoldBadges desc nulls last, SilverBadges desc nulls last, BronzeBadges desc nulls last, AnswersGiven desc nulls last
limit 100;