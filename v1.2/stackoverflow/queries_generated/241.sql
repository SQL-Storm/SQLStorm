-- {"query": "241.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2007} 
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
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        coalesce(a.AnswerCount, 0) as ActualAnswerCount,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(a.TopAnswerId, null) as TopAnswerId
    from Posts p
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxAnswerScore,
            avg(Score) as AvgAnswerScore,
            max(Id) filter (where Score = max(Score) over (partition by ParentId)) as TopAnswerId
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on p.Id = a.ParentId
    where p.PostTypeId = 1
),
PostWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.ClosedDate,
        crt.Name as CloseReasonName,
        ph.Comment as CloseReasonComment
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        sum(case when p.Score > 10 then 1 else 0 end) filter (where p.PostTypeId = 1) as HighScoreQuestions,
        sum(case when p.Score > 10 then 1 else 0 end) filter (where p.PostTypeId = 2) as HighScoreAnswers,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinkStats as (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(*) filter (where lt.Name = 'Linked') as LinkedCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
TopTagsByQuestionCount as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
        count(*) as QuestionCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by QuestionCount desc
    limit 10
),
CombinedUserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(q.QuestionCount, 0) as QuestionCount,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(b.GoldBadges, 0) as GoldBadges,
        coalesce(b.SilverBadges, 0) as SilverBadges,
        coalesce(b.BronzeBadges, 0) as BronzeBadges
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) q on u.Id = q.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) a on u.Id = a.OwnerUserId
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        group by UserId
    ) c on u.Id = c.UserId
    left join (
        select UserId,
            count(*) filter (where VoteTypeId = 2) as UpVotes,
            count(*) filter (where VoteTypeId = 3) as DownVotes
        from Votes
        group by UserId
    ) v on u.Id = v.UserId
    left join (
        select UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
)
select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.TopAnswerId,
    dls.DuplicateCount,
    dls.LinkedCount,
    pti.CloseReasonName,
    pti.ClosedDate,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.Reputation,
    us.Location,
    us.RankByReputation,
    ts.Tag,
    ts.QuestionCount as TagQuestionCount,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.HighScoreQuestions,
    ua.HighScoreAnswers
from PostAnswerStats pas
join Posts p on p.Id = pas.QuestionId
left join DuplicateLinkStats dls on dls.PostId = p.Id
left join PostWithCloseInfo pti on pti.Id = p.Id
left join UserReputationStats us on us.UserId = p.OwnerUserId
left join UserActivityWindow ua on ua.UserId = p.OwnerUserId
left join TopTagsByQuestionCount ts on ts.Tag = any(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'))
where p.Score > (
    select avg(Score) from Posts where PostTypeId = 1
)
and (pti.ClosedDate is null or pti.ClosedDate > now() - interval '30 days')
order by p.Score desc, pas.MaxAnswerScore desc
limit 50;