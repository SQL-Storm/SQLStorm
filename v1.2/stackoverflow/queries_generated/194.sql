-- {"query": "194.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1984} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsRequired = 1 and t.IsModeratorOnly = 0
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > current_date - interval '1 year'
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000 and u.Location is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    where p.CreationDate > current_date - interval '6 months'
),
PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.Score) filter (where p.OwnerUserId = u.Id) as MaxPostScore,
        min(p.CreationDate) filter (where p.OwnerUserId = u.Id) as FirstPostDate,
        max(p.CreationDate) filter (where p.OwnerUserId = u.Id) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserBadgeSummary as (
    select
        ubc.UserId,
        sum(case when ubc.Class = 1 then ubc.BadgeCount else 0 end) as GoldBadges,
        sum(case when ubc.Class = 2 then ubc.BadgeCount else 0 end) as SilverBadges,
        sum(case when ubc.Class = 3 then ubc.BadgeCount else 0 end) as BronzeBadges
    from UserBadgeCounts ubc
    group by ubc.UserId
),
FinalUserStats as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.CloseReopenEvents,
        uas.CommentsMade,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        uas.MaxPostScore,
        uas.FirstPostDate,
        uas.LastPostDate,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
        (uas.AnswersPosted::float / nullif(uas.QuestionsPosted,0)) as AnswerToQuestionRatio,
        case
            when uas.LastPostDate is not null and uas.FirstPostDate is not null then
                extract(epoch from (uas.LastPostDate - uas.FirstPostDate))/86400.0
            else null
        end as ActiveDaysSpan
    from UserActivitySummary uas
    left join UserBadgeSummary ubs on ubs.UserId = uas.UserId
)
select
    fus.UserId,
    fus.DisplayName,
    fus.QuestionsPosted,
    fus.AnswersPosted,
    fus.AnswerToQuestionRatio,
    fus.CloseReopenEvents,
    fus.CommentsMade,
    fus.UpVotesGiven,
    fus.DownVotesGiven,
    fus.MaxPostScore,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.ActiveDaysSpan,
    urw.LocationRank,
    string_agg(distinct rth.TagName, ', ') as RequiredTagsUsed,
    coalesce(pld.DuplicateCount, 0) as DuplicateLinksCount,
    case
        when fus.AnswerToQuestionRatio > 2 and fus.GoldBadges > 0 then 'Expert Answerer'
        when fus.QuestionsPosted > 50 then 'Active Questioner'
        else 'Regular User'
    end as UserCategory
from FinalUserStats fus
left join UserReputationWindow urw on urw.Id = fus.UserId
left join (
    select
        p.OwnerUserId,
        count(distinct pl.Id) as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    where p.OwnerUserId is not null
    group by p.OwnerUserId
) pld on pld.OwnerUserId = fus.UserId
left join RecursiveTagHierarchy rth on rth.Id = any(
    select unnest(string_to_array(
        regexp_replace(coalesce(p.Tags, ''), '[<>]', ' ', 'g'), ' '
    )::int[])
)
left join Posts p on p.OwnerUserId = fus.UserId and p.Tags is not null
group by
    fus.UserId,
    fus.DisplayName,
    fus.QuestionsPosted,
    fus.AnswersPosted,
    fus.AnswerToQuestionRatio,
    fus.CloseReopenEvents,
    fus.CommentsMade,
    fus.UpVotesGiven,
    fus.DownVotesGiven,
    fus.MaxPostScore,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.ActiveDaysSpan,
    urw.LocationRank,
    pld.DuplicateCount
order by fus.AnswersPosted desc, fus.GoldBadges desc, fus.MaxPostScore desc
limit 100;