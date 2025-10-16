-- {"query": "354.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1715} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        coalesce(u.AboutMe, '') as AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ubc.Class,
        ubc.BadgeCount,
        row_number() over (partition by u.Id order by ubc.Class) as BadgeRank
    from Users u
    left join UserBadgeCounts ubc on u.Id = ubc.UserId
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1
),
AnswersWithScores as (
    select
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.Body,
        a.CommentCount,
        a.FavoriteCount,
        p.Score as ParentQuestionScore,
        p.ViewCount as ParentQuestionViews,
        p.Tags as ParentTags
    from Posts a
    join Posts p on a.ParentId = p.Id
    where a.PostTypeId = 2
),
VotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as TotalComments,
        avg(c.Score) as AvgCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
ComplexUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.WebsiteUrl,
        ua.AboutMe,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        coalesce(ucs.TotalComments, 0) as TotalComments,
        coalesce(ucs.AvgCommentScore, 0) as AvgCommentScore,
        coalesce(ucs.LastCommentDate, '1900-01-01'::timestamp) as LastCommentDate
    from UserActivity ua
    left join UserBadgeCounts ubc_gold on ua.UserId = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ua.UserId = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ua.UserId = ubc_bronze.UserId and ubc_bronze.Class = 3
    left join UserCommentStats ucs on ua.UserId = ucs.UserId
),
FilteredQuestions as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.Tags,
        tq.AnswerCount,
        tq.FavoriteCount,
        tq.ClosedDate,
        tq.AcceptedAnswerId,
        phcr.CloseReason,
        phcr.CloseDate,
        vs.UpVotes,
        vs.DownVotes,
        vs.Favorites,
        vs.CloseVotes
    from TopQuestions tq
    left join PostHistoryCloseReasons phcr on tq.Id = phcr.PostId
    left join VotesSummary vs on tq.Id = vs.PostId
    where (tq.Score > 10 or tq.ViewCount > 1000)
      and (phcr.CloseDate is null or phcr.CloseDate > now() - interval '30 days')
),
AnswerAggregates as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
        sum(case when a.Score <= 0 then 1 else 0 end) as NonPositiveAnswers
    from AnswersWithScores a
    group by a.ParentId
),
FinalResult as (
    select
        fq.Id as QuestionId,
        fq.Title,
        fq.OwnerUserId,
        cu.DisplayName as OwnerDisplayName,
        fq.CreationDate,
        fq.Score,
        fq.ViewCount,
        fq.Tags,
        fq.AnswerCount,
        fq.FavoriteCount,
        fq.ClosedDate,
        fq.CloseReason,
        fq.CloseDate,
        fq.AcceptedAnswerId,
        fq.UpVotes,
        fq.DownVotes,
        fq.Favorites,
        fq.CloseVotes,
        aa.TotalAnswers,
        aa.AvgAnswerScore,
        aa.MaxAnswerScore,
        aa.PositiveAnswers,
        aa.NonPositiveAnswers,
        cu.Reputation,
        cu.GoldBadges,
        cu.SilverBadges,
        cu.BronzeBadges,
        cu.TotalComments,
        cu.AvgCommentScore,
        cu.LastCommentDate,
        -- Complex string expression: concatenate tags and owner location with conditional NULL logic
        concat_ws(' | ',
            coalesce(fq.Tags, 'NoTags'),
            coalesce(cu.Location, 'NoLocation'),
            case when fq.ClosedDate is not null then 'Closed' else 'Open' end
        ) as TagLocationStatus,
        -- Window function: rank questions by score within each owner
        rank() over (partition by fq.OwnerUserId order by fq.Score desc) as OwnerQuestionRank
    from FilteredQuestions fq
    left join AnswerAggregates aa on fq.Id = aa.QuestionId
    left join ComplexUserStats cu on fq.OwnerUserId = cu.UserId
)
select *
from FinalResult
where OwnerQuestionRank <= 5
order by Score desc, ViewCount desc
limit 100;