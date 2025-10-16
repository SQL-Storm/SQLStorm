-- {"query": "487.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1756} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        avg(p.Score) filter (where p.OwnerUserId = u.Id and p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.OwnerUserId = u.Id and p.PostTypeId in (1,2)) as MaxPostScore,
        min(p.Score) filter (where p.OwnerUserId = u.Id and p.PostTypeId in (1,2)) as MinPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), UserScoreRanks as (
    select 
        UserId,
        DisplayName,
        Reputation,
        CreationDate,
        LastAccessDate,
        QuestionCount,
        AnswerCount,
        CommentCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        AvgPostScore,
        MaxPostScore,
        MinPostScore,
        rank() over (order by Reputation desc nulls last) as ReputationRank,
        dense_rank() over (order by GoldBadges desc, SilverBadges desc, BronzeBadges desc) as BadgeRank
    from RecursiveUserActivity
), TopUsersCTE as (
    select * from UserScoreRanks
    where ReputationRank <= 50
), QuestionTagStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        u.UserId,
        u.DisplayName as OwnerName,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    join TopUsersCTE u on p.OwnerUserId = u.UserId
    where p.PostTypeId = 1
), TagAggregates as (
    select 
        Tag,
        count(distinct QuestionId) as QuestionsCount,
        avg(Score) as AvgScore,
        avg(ViewCount) as AvgViews,
        avg(AnswerCount) as AvgAnswers,
        sum(FavoriteCount) as TotalFavorites
    from QuestionTagStats
    group by Tag
), TagWithDuplicates as (
    select 
        ta.Tag,
        ta.QuestionsCount,
        ta.AvgScore,
        ta.AvgViews,
        ta.AvgAnswers,
        ta.TotalFavorites,
        coalesce(dup.DuplicateCount, 0) as DuplicateCount
    from TagAggregates ta
    left join (
        select 
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            count(pl.Id) as DuplicateCount
        from Posts p
        join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
        where p.PostTypeId = 1
        group by Tag
    ) dup on dup.Tag = ta.Tag
), UserTopPosts as (
    select 
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    where p.PostTypeId in (1,2)
), UserTopPostDetails as (
    select 
        utp.OwnerUserId,
        utp.PostId,
        utp.PostTypeId,
        utp.Score,
        utp.CreationDate,
        utp.Title,
        case when utp.PostTypeId = 1 then 'Question'
             when utp.PostTypeId = 2 then 'Answer'
             else 'Other' end as PostTypeName,
        coalesce(a.Score, 0) as AcceptedAnswerScore
    from UserTopPosts utp
    left join Posts a on a.Id = (select AcceptedAnswerId from Posts where Id = utp.PostId) and utp.PostTypeId = 1
    where utp.PostRank <= 3
), UserActivitySummary as (
    select 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.QuestionCount,
        u.AnswerCount,
        u.CommentCount,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        utpd.PostId,
        utpd.PostTypeName,
        utpd.Score as PostScore,
        utpd.CreationDate as PostCreationDate,
        utpd.Title as PostTitle,
        utpd.AcceptedAnswerScore
    from TopUsersCTE u
    left join UserTopPostDetails utpd on utpd.OwnerUserId = u.UserId
), FinalResults as (
    select 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.CreationDate,
        uas.LastAccessDate,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.CommentCount,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        uas.PostId,
        uas.PostTypeName,
        uas.PostScore,
        uas.PostCreationDate,
        uas.PostTitle,
        uas.AcceptedAnswerScore,
        twd.Tag,
        twd.QuestionsCount,
        twd.AvgScore as TagAvgScore,
        twd.AvgViews as TagAvgViews,
        twd.AvgAnswers as TagAvgAnswers,
        twd.TotalFavorites,
        twd.DuplicateCount,
        case 
            when uas.Reputation > 10000 and uas.GoldBadges > 5 then 'Elite'
            when uas.Reputation between 5000 and 10000 then 'Experienced'
            when uas.Reputation between 1000 and 4999 then 'Intermediate'
            else 'Novice' end as UserLevel,
        row_number() over (partition by uas.UserId order by uas.PostScore desc nulls last) as PostRankPerUser
    from UserActivitySummary uas
    left join QuestionTagStats qts on qts.UserId = uas.UserId and qts.QuestionId = uas.PostId
    left join TagWithDuplicates twd on twd.Tag = qts.Tag
)
select 
    UserId,
    DisplayName,
    Reputation,
    to_char(CreationDate, 'YYYY-MM-DD') as UserCreated,
    to_char(LastAccessDate, 'YYYY-MM-DD') as LastAccess,
    QuestionCount,
    AnswerCount,
    CommentCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostId,
    PostTypeName,
    PostScore,
    to_char(PostCreationDate, 'YYYY-MM-DD') as PostCreated,
    coalesce(PostTitle, '(no title)') as PostTitle,
    AcceptedAnswerScore,
    coalesce(Tag, '(no tag)') as Tag,
    QuestionsCount,
    round(TagAvgScore::numeric, 2) as TagAvgScore,
    round(TagAvgViews::numeric, 2) as TagAvgViews,
    round(TagAvgAnswers::numeric, 2) as TagAvgAnswers,
    TotalFavorites,
    DuplicateCount,
    UserLevel,
    PostRankPerUser
from FinalResults
where PostRankPerUser <= 3
order by Reputation desc, UserId, PostRankPerUser;